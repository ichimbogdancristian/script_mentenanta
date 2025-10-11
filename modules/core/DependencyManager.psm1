#Requires -Version 7.0

<#
.SYNOPSIS
    Dependency Manager Module - Core Infrastructure

.DESCRIPTION
    Manages installation, verification, and updates of package manager dependencies
    including winget, chocolatey, PowerShell 7, NuGet, and PSWindowsUpdate module.

.NOTES
    Module Type: Core Infrastructure
    Dependencies: Internet connection, Administrator privileges
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Public Functions

<#
.SYNOPSIS
    Ensures all required dependencies are installed and configured

.DESCRIPTION
    Checks for and installs missing dependencies in the correct order:
    1. PowerShell 7+ (if not present)
    2. winget (Windows Package Manager)
    3. NuGet provider
    4. PowerShellGet module
    5. PSWindowsUpdate module
    6. Chocolatey package manager

.PARAMETER Force
    Force reinstallation of dependencies even if they exist

.PARAMETER SkipChocolatey
    Skip chocolatey installation

.PARAMETER SkipPSWindowsUpdate
    Skip PSWindowsUpdate module installation

.EXAMPLE
    $result = Install-AllDependencies

.EXAMPLE
    $result = Install-AllDependencies -SkipChocolatey -Force
#>
function Install-AllDependencies {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SkipChocolatey,

        [Parameter()]
        [switch]$SkipPSWindowsUpdate
    )

    Write-Host "🔧 Installing and configuring package manager dependencies..." -ForegroundColor Cyan
    $startTime = Get-Date

    # Initialize results tracking
    $results = @{
        TotalDependencies = 0
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
        Dependencies = @{
            PowerShell7 = @{ Status = 'Unknown'; Version = $null; Error = $null }
            WinGet = @{ Status = 'Unknown'; Version = $null; Error = $null }
            NuGet = @{ Status = 'Unknown'; Version = $null; Error = $null }
            PowerShellGet = @{ Status = 'Unknown'; Version = $null; Error = $null }
            PSWindowsUpdate = @{ Status = 'Unknown'; Version = $null; Error = $null }
            Chocolatey = @{ Status = 'Unknown'; Version = $null; Error = $null }
        }
    }

    try {
        # 1. PowerShell 7+ Check
        Write-Host "  🐚 Checking PowerShell 7..." -ForegroundColor Gray
        $results.TotalDependencies++
        $psResult = Test-PowerShell7Installation
        $results.Dependencies.PowerShell7 = $psResult

        if ($psResult.Status -eq 'Installed') {
            Write-Host "    ✅ PowerShell 7 is available: v$($psResult.Version)" -ForegroundColor Green
            $results.Successful++
        }
        elseif ($psResult.Status -eq 'Missing') {
            Write-Host "    ❌ PowerShell 7 not found - current session is $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
            Write-Host "    💡 Install PowerShell 7 from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Blue
            $results.Failed++
        }

        # 2. WinGet Installation
        Write-Host "  📦 Installing winget..." -ForegroundColor Gray
        $results.TotalDependencies++
        $wingetResult = Install-WinGetPackageManager -Force:$Force
        $results.Dependencies.WinGet = $wingetResult

        if ($wingetResult.Status -eq 'Installed') {
            Write-Host "    ✅ winget is ready: v$($wingetResult.Version)" -ForegroundColor Green
            $results.Successful++
        } else {
            Write-Host "    ❌ winget installation failed: $($wingetResult.Error)" -ForegroundColor Red
            $results.Failed++
        }

        # 3. NuGet Provider
        Write-Host "  📚 Configuring NuGet provider..." -ForegroundColor Gray
        $results.TotalDependencies++
        $nugetResult = Install-NuGetProvider -Force:$Force
        $results.Dependencies.NuGet = $nugetResult

        if ($nugetResult.Status -eq 'Installed') {
            Write-Host "    ✅ NuGet provider is ready: v$($nugetResult.Version)" -ForegroundColor Green
            $results.Successful++
        } else {
            Write-Host "    ❌ NuGet provider installation failed: $($nugetResult.Error)" -ForegroundColor Red
            $results.Failed++
        }

        # 4. PowerShellGet Module
        Write-Host "  🔄 Updating PowerShellGet..." -ForegroundColor Gray
        $results.TotalDependencies++
        $psgetResult = Install-PowerShellGetModule -Force:$Force
        $results.Dependencies.PowerShellGet = $psgetResult

        if ($psgetResult.Status -eq 'Installed') {
            Write-Host "    ✅ PowerShellGet is ready: v$($psgetResult.Version)" -ForegroundColor Green
            $results.Successful++
        } else {
            Write-Host "    ❌ PowerShellGet update failed: $($psgetResult.Error)" -ForegroundColor Red
            $results.Failed++
        }

        # 5. PSWindowsUpdate Module
        if (-not $SkipPSWindowsUpdate) {
            Write-Host "  🔄 Installing PSWindowsUpdate module..." -ForegroundColor Gray
            $results.TotalDependencies++
            $pswuResult = Install-PSWindowsUpdateModule -Force:$Force
            $results.Dependencies.PSWindowsUpdate = $pswuResult

            if ($pswuResult.Status -eq 'Installed') {
                Write-Host "    ✅ PSWindowsUpdate is ready: v$($pswuResult.Version)" -ForegroundColor Green
                $results.Successful++
            } else {
                Write-Host "    ❌ PSWindowsUpdate installation failed: $($pswuResult.Error)" -ForegroundColor Red
                $results.Failed++
            }
        } else {
            Write-Host "  ⏭️  Skipping PSWindowsUpdate module installation" -ForegroundColor Yellow
            $results.Dependencies.PSWindowsUpdate.Status = 'Skipped'
            $results.Skipped++
        }

        # 6. Chocolatey
        if (-not $SkipChocolatey) {
            Write-Host "  🍫 Installing Chocolatey..." -ForegroundColor Gray
            $results.TotalDependencies++
            $chocoResult = Install-ChocolateyPackageManager -Force:$Force
            $results.Dependencies.Chocolatey = $chocoResult

            if ($chocoResult.Status -eq 'Installed') {
                Write-Host "    ✅ Chocolatey is ready: v$($chocoResult.Version)" -ForegroundColor Green
                $results.Successful++
            } else {
                Write-Host "    ❌ Chocolatey installation failed: $($chocoResult.Error)" -ForegroundColor Red
                $results.Failed++
            }
        } else {
            Write-Host "  ⏭️  Skipping Chocolatey installation" -ForegroundColor Yellow
            $results.Dependencies.Chocolatey.Status = 'Skipped'
            $results.Skipped++
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary
        $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
        Write-Host "  $statusIcon Dependency installation completed in $([math]::Round($duration, 2))s" -ForegroundColor Green
        Write-Host "    📊 Total: $($results.TotalDependencies), Success: $($results.Successful), Failed: $($results.Failed), Skipped: $($results.Skipped)" -ForegroundColor Gray

        if ($results.Failed -gt 0) {
            Write-Host "    ⚠️  Some dependencies failed to install. Check individual results." -ForegroundColor Yellow
        }

        return $results
    }
    catch {
        Write-Error "Dependency installation failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets the current status of all package manager dependencies

.DESCRIPTION
    Checks installation status and versions of all package managers and modules.

.EXAMPLE
    $status = Get-DependencyStatus
#>
function Get-DependencyStatus {
    [CmdletBinding()]
    param()

    Write-Host "📋 Checking dependency status..." -ForegroundColor Cyan

    $status = @{
        Timestamp = Get-Date
        Dependencies = @{
            PowerShell7 = Test-PowerShell7Installation
            WinGet = Test-WinGetInstallation
            NuGet = Test-NuGetProvider
            PowerShellGet = Test-PowerShellGetModule
            PSWindowsUpdate = Test-PSWindowsUpdateModule
            Chocolatey = Test-ChocolateyInstallation
        }
        Summary = @{
            TotalChecked = 6
            Available = 0
            Missing = 0
            Errors = 0
        }
    }

    # Calculate summary
    foreach ($dep in $status.Dependencies.Values) {
        switch ($dep.Status) {
            'Installed' { $status.Summary.Available++ }
            'Missing' { $status.Summary.Missing++ }
            'Error' { $status.Summary.Errors++ }
        }
    }

    # Display results
    foreach ($depName in $status.Dependencies.Keys) {
        $dep = $status.Dependencies[$depName]
        $icon = switch ($dep.Status) {
            'Installed' { "✅" }
            'Missing' { "❌" }
            'Error' { "⚠️" }
            default { "❓" }
        }

        $versionInfo = if ($dep.Version) { " (v$($dep.Version))" } else { "" }
        Write-Host "  $icon $depName`: $($dep.Status)$versionInfo" -ForegroundColor Gray

        if ($dep.Error) {
            Write-Host "      Error: $($dep.Error)" -ForegroundColor Red
        }
    }

    Write-Host "  📊 Summary: $($status.Summary.Available) available, $($status.Summary.Missing) missing, $($status.Summary.Errors) errors" -ForegroundColor Gray

    return $status
}

#endregion

#region PowerShell 7 Management

function Test-PowerShell7Installation {
    try {
        # Check current PowerShell version
        $currentVersion = $PSVersionTable.PSVersion

        if ($currentVersion.Major -ge 7) {
            return @{
                Status = 'Installed'
                Version = $currentVersion.ToString()
                Error = $null
            }
        }

        # Check if PowerShell 7 is available in PATH
        $pwshPath = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if ($pwshPath) {
            $versionOutput = & pwsh --version 2>$null
            if ($versionOutput -match 'PowerShell\s+([\d\.]+)') {
                return @{
                    Status = 'Installed'
                    Version = $matches[1]
                    Error = $null
                }
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "PowerShell 7+ not found. Current version: $currentVersion"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region WinGet Management

function Install-WinGetPackageManager {
    [CmdletBinding()]
    param([switch]$Force)

    try {
        # Check if winget is already available
        if (-not $Force) {
            $existing = Test-WinGetInstallation
            if ($existing.Status -eq 'Installed') {
                return $existing
            }
        }

        Write-Host "    🔄 Installing winget package manager..." -ForegroundColor Blue

        # Try to install via Microsoft Store or GitHub
        try {
            # Method 1: Try to get from Microsoft Store (Windows 10 1809+)
            $appxPackages = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue

            if (-not $appxPackages) {
                Write-Host "      📥 Installing App Installer from Microsoft Store..." -ForegroundColor Gray

                # Download and install the latest release
                $downloadUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $tempFile = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"

                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing
                Add-AppxPackage -Path $tempFile -Force
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }

            # Refresh environment
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')

            # Verify installation
            Start-Sleep -Seconds 3
            return Test-WinGetInstallation
        }
        catch {
            return @{
                Status = 'Error'
                Version = $null
                Error = "Installation failed: $($_.Exception.Message)"
            }
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-WinGetInstallation {
    try {
        $wingetPath = Get-Command 'winget' -ErrorAction SilentlyContinue
        if ($wingetPath) {
            $versionOutput = & winget --version 2>$null
            if ($versionOutput -match 'v([\d\.]+)') {
                return @{
                    Status = 'Installed'
                    Version = $matches[1]
                    Error = $null
                }
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "winget command not found"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region NuGet Provider Management

function Install-NuGetProvider {
    [CmdletBinding()]
    param([switch]$Force)

    try {
        if (-not $Force) {
            $existing = Test-NuGetProvider
            if ($existing.Status -eq 'Installed') {
                return $existing
            }
        }

        Write-Host "    🔄 Installing NuGet provider..." -ForegroundColor Blue

        # Install NuGet provider with prompts suppressed
        $originalProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false
            Import-PackageProvider -Name NuGet -Force

            # Set PSGallery as trusted repository
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

            return Test-NuGetProvider
        }
        finally {
            $ProgressPreference = $originalProgressPreference
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-NuGetProvider {
    try {
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($nugetProvider) {
            return @{
                Status = 'Installed'
                Version = $nugetProvider.Version.ToString()
                Error = $null
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "NuGet provider not found"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region PowerShellGet Management

function Install-PowerShellGetModule {
    [CmdletBinding()]
    param([switch]$Force)

    try {
        if (-not $Force) {
            $existing = Test-PowerShellGetModule
            if ($existing.Status -eq 'Installed') {
                return $existing
            }
        }

        Write-Host "    🔄 Updating PowerShellGet module..." -ForegroundColor Blue

        $originalProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        try {
            # Update PowerShellGet to latest version
            Install-Module -Name PowerShellGet -Force -Scope AllUsers -AllowClobber -Confirm:$false
            Import-Module PowerShellGet -Force

            return Test-PowerShellGetModule
        }
        finally {
            $ProgressPreference = $originalProgressPreference
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-PowerShellGetModule {
    try {
        $psgetModule = Get-Module -Name PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($psgetModule) {
            return @{
                Status = 'Installed'
                Version = $psgetModule.Version.ToString()
                Error = $null
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "PowerShellGet module not found"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region PSWindowsUpdate Management

function Install-PSWindowsUpdateModule {
    [CmdletBinding()]
    param([switch]$Force)

    try {
        if (-not $Force) {
            $existing = Test-PSWindowsUpdateModule
            if ($existing.Status -eq 'Installed') {
                return $existing
            }
        }

        Write-Host "    🔄 Installing PSWindowsUpdate module..." -ForegroundColor Blue

        $originalProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        try {
            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false
            Import-Module PSWindowsUpdate -Force

            return Test-PSWindowsUpdateModule
        }
        finally {
            $ProgressPreference = $originalProgressPreference
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-PSWindowsUpdateModule {
    try {
        $pswuModule = Get-Module -Name PSWindowsUpdate -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($pswuModule) {
            return @{
                Status = 'Installed'
                Version = $pswuModule.Version.ToString()
                Error = $null
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "PSWindowsUpdate module not found"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region Chocolatey Management

function Install-ChocolateyPackageManager {
    [CmdletBinding()]
    param([switch]$Force)

    try {
        if (-not $Force) {
            $existing = Test-ChocolateyInstallation
            if ($existing.Status -eq 'Installed') {
                return $existing
            }
        }

        Write-Host "    🔄 Installing Chocolatey package manager..." -ForegroundColor Blue

        # Set execution policy temporarily
        $originalPolicy = Get-ExecutionPolicy
        Set-ExecutionPolicy Bypass -Scope Process -Force

        try {
            # Download and execute chocolatey installation script
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

            # Refresh environment variables
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')

            # Verify installation
            return Test-ChocolateyInstallation
        }
        finally {
            Set-ExecutionPolicy $originalPolicy -Scope Process -Force
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

function Test-ChocolateyInstallation {
    try {
        $chocoPath = Get-Command 'choco' -ErrorAction SilentlyContinue
        if ($chocoPath) {
            $versionOutput = & choco --version 2>$null
            if ($versionOutput -match '([\d\.]+)') {
                return @{
                    Status = 'Installed'
                    Version = $matches[1]
                    Error = $null
                }
            }
        }

        return @{
            Status = 'Missing'
            Version = $null
            Error = "Chocolatey command not found"
        }
    }
    catch {
        return @{
            Status = 'Error'
            Version = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Install-AllDependencies',
    'Get-DependencyStatus'
)
