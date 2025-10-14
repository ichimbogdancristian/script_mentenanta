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
    $result = Install-AllDependency

.EXAMPLE
    $result = Install-AllDependency -SkipChocolatey -Force
#>
function Install-AllDependency {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SkipChocolatey,

        [Parameter()]
        [switch]$SkipPSWindowsUpdate
    )

    Write-Information "🔧 Installing and configuring package manager dependencies..." -InformationAction Continue
    $startTime = Get-Date

    # Initialize results tracking
    $results = @{
        TotalDependencies = 0
        Successful        = 0
        Failed            = 0
        Skipped           = 0
        Details           = [List[PSCustomObject]]::new()
        Dependencies      = @{
            PowerShell7     = @{ Status = 'Unknown'; Version = $null; Error = $null }
            WinGet          = @{ Status = 'Unknown'; Version = $null; Error = $null }
            NuGet           = @{ Status = 'Unknown'; Version = $null; Error = $null }
            PowerShellGet   = @{ Status = 'Unknown'; Version = $null; Error = $null }
            PSWindowsUpdate = @{ Status = 'Unknown'; Version = $null; Error = $null }
            Chocolatey      = @{ Status = 'Unknown'; Version = $null; Error = $null }
        }
    }

    try {
        # 1. PowerShell 7+ Check
        Write-Information "  🐚 Checking PowerShell 7..." -InformationAction Continue
        $results.TotalDependencies++
        $psResult = Test-PowerShell7Installation
        $results.Dependencies.PowerShell7 = $psResult

        if ($psResult.Status -eq 'Installed') {
            Write-Information "    ✅ PowerShell 7 is available: v$($psResult.Version)" -InformationAction Continue
            $results.Successful++
        }
        elseif ($psResult.Status -eq 'Missing') {
            Write-Information "    ❌ PowerShell 7 not found - current session is $($PSVersionTable.PSVersion)" -InformationAction Continue
            Write-Information "    💡 Install PowerShell 7 from: https://github.com/PowerShell/PowerShell/releases" -InformationAction Continue
            $results.Failed++
        }

        # 2. WinGet Installation
        Write-Information "  📦 Installing winget..." -InformationAction Continue
        $results.TotalDependencies++
        $wingetResult = Install-WinGetPackageManager -Force:$Force
        $results.Dependencies.WinGet = $wingetResult

        if ($wingetResult.Status -eq 'Installed') {
            Write-Information "    ✅ winget is ready: v$($wingetResult.Version)" -InformationAction Continue
            $results.Successful++
        }
        else {
            Write-Information "    ❌ winget installation failed: $($wingetResult.Error)" -InformationAction Continue
            $results.Failed++
        }

        # 3. NuGet Provider
        Write-Information "  📚 Configuring NuGet provider..." -InformationAction Continue
        $results.TotalDependencies++
        $nugetResult = Install-NuGetProvider -Force:$Force
        $results.Dependencies.NuGet = $nugetResult

        if ($nugetResult.Status -eq 'Installed') {
            Write-Information "    ✅ NuGet provider is ready: v$($nugetResult.Version)" -InformationAction Continue
            $results.Successful++
        }
        else {
            Write-Information "    ❌ NuGet provider installation failed: $($nugetResult.Error)" -InformationAction Continue
            $results.Failed++
        }

        # 4. PowerShellGet Module
        Write-Information "  🔄 Updating PowerShellGet..." -InformationAction Continue
        $results.TotalDependencies++
        $psgetResult = Install-PowerShellGetModule -Force:$Force
        $results.Dependencies.PowerShellGet = $psgetResult

        if ($psgetResult.Status -eq 'Installed') {
            Write-Information "    ✅ PowerShellGet is ready: v$($psgetResult.Version)" -InformationAction Continue
            $results.Successful++
        }
        else {
            Write-Information "    ❌ PowerShellGet update failed: $($psgetResult.Error)" -InformationAction Continue
            $results.Failed++
        }

        # 5. PSWindowsUpdate Module
        if (-not $SkipPSWindowsUpdate) {
            Write-Information "  🔄 Installing PSWindowsUpdate module..." -InformationAction Continue
            $results.TotalDependencies++
            $pswuResult = Install-PSWindowsUpdateModule -Force:$Force
            $results.Dependencies.PSWindowsUpdate = $pswuResult

            if ($pswuResult.Status -eq 'Installed') {
                Write-Information "    ✅ PSWindowsUpdate is ready: v$($pswuResult.Version)" -InformationAction Continue
                $results.Successful++
            }
            else {
                Write-Information "    ❌ PSWindowsUpdate installation failed: $($pswuResult.Error)" -InformationAction Continue
                $results.Failed++
            }
        }
        else {
            Write-Information "  ⏭️  Skipping PSWindowsUpdate module installation" -InformationAction Continue
            $results.Dependencies.PSWindowsUpdate.Status = 'Skipped'
            $results.Skipped++
        }

        # 6. Chocolatey
        if (-not $SkipChocolatey) {
            Write-Information "  🍫 Installing Chocolatey..." -InformationAction Continue
            $results.TotalDependencies++
            $chocoResult = Install-ChocolateyPackageManager -Force:$Force
            $results.Dependencies.Chocolatey = $chocoResult

            if ($chocoResult.Status -eq 'Installed') {
                Write-Information "    ✅ Chocolatey is ready: v$($chocoResult.Version)" -InformationAction Continue
                $results.Successful++
            }
            else {
                Write-Information "    ❌ Chocolatey installation failed: $($chocoResult.Error)" -InformationAction Continue
                $results.Failed++
            }
        }
        else {
            Write-Information "  ⏭️  Skipping Chocolatey installation" -InformationAction Continue
            $results.Dependencies.Chocolatey.Status = 'Skipped'
            $results.Skipped++
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary
        $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
        Write-Information "  $statusIcon Dependency installation completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "    📊 Total: $($results.TotalDependencies), Success: $($results.Successful), Failed: $($results.Failed), Skipped: $($results.Skipped)" -InformationAction Continue

        if ($results.Failed -gt 0) {
            Write-Information "    ⚠️  Some dependencies failed to install. Check individual results." -InformationAction Continue
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

    Write-Information "📋 Checking dependency status..." -InformationAction Continue

    $status = @{
        Timestamp    = Get-Date
        Dependencies = @{
            PowerShell7     = Test-PowerShell7Installation
            WinGet          = Test-WinGetInstallation
            NuGet           = Test-NuGetProvider
            PowerShellGet   = Test-PowerShellGetModule
            PSWindowsUpdate = Test-PSWindowsUpdateModule
            Chocolatey      = Test-ChocolateyInstallation
        }
        Summary      = @{
            TotalChecked = 6
            Available    = 0
            Missing      = 0
            Errors       = 0
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
        Write-Information "  $icon $depName`: $($dep.Status)$versionInfo" -InformationAction Continue

        if ($dep.Error) {
            Write-Information "      Error: $($dep.Error)" -InformationAction Continue
        }
    }

    Write-Information "  📊 Summary: $($status.Summary.Available) available, $($status.Summary.Missing) missing, $($status.Summary.Errors) errors" -InformationAction Continue

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
                Status  = 'Installed'
                Version = $currentVersion.ToString()
                Error   = $null
            }
        }

        # Check if PowerShell 7 is available in PATH
        $pwshPath = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if ($pwshPath) {
            $versionOutput = & pwsh --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $versionOutput -match 'PowerShell\s+([\d\.]+)') {
                return @{
                    Status  = 'Installed'
                    Version = $matches[1]
                    Error   = $null
                }
            }
            elseif ($LASTEXITCODE -ne 0) {
                return @{
                    Status  = 'Error'
                    Version = $null
                    Error   = "pwsh command failed with exit code: $LASTEXITCODE"
                }
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "PowerShell 7+ not found. Current version: $currentVersion"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
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

        Write-Information "    🔄 Installing winget package manager..." -InformationAction Continue

        # Try to install via Microsoft Store or GitHub
        try {
            # Method 1: Try to get from Microsoft Store (Windows 10 1809+)
            $appxPackages = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue

            if (-not $appxPackages) {
                Write-Information "      📥 Installing App Installer from Microsoft Store..." -InformationAction Continue

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
                Status  = 'Error'
                Version = $null
                Error   = "Installation failed: $($_.Exception.Message)"
            }
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

function Test-WinGetInstallation {
    try {
        $wingetPath = Get-Command 'winget' -ErrorAction SilentlyContinue
        if ($wingetPath) {
            $versionOutput = & winget --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $versionOutput -match 'v([\d\.]+)') {
                return @{
                    Status  = 'Installed'
                    Version = $matches[1]
                    Error   = $null
                }
            }
            elseif ($LASTEXITCODE -ne 0) {
                return @{
                    Status  = 'Error'
                    Version = $null
                    Error   = "winget command failed with exit code: $LASTEXITCODE"
                }
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "winget command not found"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
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

        Write-Information "    🔄 Installing NuGet provider..." -InformationAction Continue

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
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

function Test-NuGetProvider {
    try {
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($nugetProvider) {
            return @{
                Status  = 'Installed'
                Version = $nugetProvider.Version.ToString()
                Error   = $null
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "NuGet provider not found"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
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

        Write-Information "    🔄 Updating PowerShellGet module..." -InformationAction Continue

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
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

function Test-PowerShellGetModule {
    try {
        $psgetModule = Get-Module -Name PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($psgetModule) {
            return @{
                Status  = 'Installed'
                Version = $psgetModule.Version.ToString()
                Error   = $null
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "PowerShellGet module not found"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
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

        Write-Information "    🔄 Installing PSWindowsUpdate module..." -InformationAction Continue

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
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

function Test-PSWindowsUpdateModule {
    try {
        $pswuModule = Get-Module -Name PSWindowsUpdate -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ($pswuModule) {
            return @{
                Status  = 'Installed'
                Version = $pswuModule.Version.ToString()
                Error   = $null
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "PSWindowsUpdate module not found"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
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

        Write-Information "    🔄 Installing Chocolatey package manager..." -InformationAction Continue

        # Set execution policy temporarily
        $originalPolicy = Get-ExecutionPolicy
        Set-ExecutionPolicy Bypass -Scope Process -Force

        try {
            # Download chocolatey installation script to a temporary file
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            $tempFile = [System.IO.Path]::GetTempFileName() + '.ps1'
            
            try {
                (New-Object System.Net.WebClient).DownloadFile('https://community.chocolatey.org/install.ps1', $tempFile)
                
                # Execute the script using the call operator
                & $tempFile
                
                # Refresh environment variables
                $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')

                # Verify installation
                return Test-ChocolateyInstallation
            }
            finally {
                # Clean up temporary file
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        finally {
            Set-ExecutionPolicy $originalPolicy -Scope Process -Force
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

function Test-ChocolateyInstallation {
    try {
        $chocoPath = Get-Command 'choco' -ErrorAction SilentlyContinue
        if ($chocoPath) {
            $versionOutput = & choco --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $versionOutput -match '([\d\.]+)') {
                return @{
                    Status  = 'Installed'
                    Version = $matches[1]
                    Error   = $null
                }
            }
            elseif ($LASTEXITCODE -ne 0) {
                return @{
                    Status  = 'Error'
                    Version = $null
                    Error   = "choco command failed with exit code: $LASTEXITCODE"
                }
            }
        }

        return @{
            Status  = 'Missing'
            Version = $null
            Error   = "Chocolatey command not found"
        }
    }
    catch {
        return @{
            Status  = 'Error'
            Version = $null
            Error   = $_.Exception.Message
        }
    }
}

#endregion

#region Administrative Privilege Functions

<#
.SYNOPSIS
    Tests if the current PowerShell session has administrator privileges

.DESCRIPTION
    Checks if the current user is running with administrative privileges by
    testing membership in the Administrators group.

.EXAMPLE
    if (Test-AdminPrivilege) {
        Write-Host "Administrator privileges confirmed"
    }

.OUTPUTS
    [bool] True if running as administrator, False otherwise
#>
function Test-AdminPrivilege {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        
        $isAdmin = $principal.IsInRole($adminRole)
        
        Write-Verbose "Administrator privilege check: $isAdmin"
        return $isAdmin
    }
    catch {
        Write-Warning "Failed to check administrator privileges: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Asserts that administrator privileges are available and throws if not

.DESCRIPTION
    Checks for administrator privileges and throws a terminating error if not found.
    This function should be called at the start of operations that require elevated access.

.PARAMETER Operation
    Name of the operation requiring administrator privileges (for error messages)

.EXAMPLE
    Assert-AdminPrivilege -Operation "Registry modification"

.OUTPUTS
    None (throws on failure)
#>
function Assert-AdminPrivilege {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation = "This operation"
    )
    
    if (-not (Test-AdminPrivilege)) {
        $errorMessage = "$Operation requires administrator privileges. Please run PowerShell as Administrator."
        Write-Error $errorMessage -Category PermissionDenied -ErrorAction Stop
    }
    
    Write-Verbose "✓ Administrator privileges confirmed for: $Operation"
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Install-AllDependency',
    'Get-DependencyStatus',
    'Test-AdminPrivilege',
    'Assert-AdminPrivilege'
)

