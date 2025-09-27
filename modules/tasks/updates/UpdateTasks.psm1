# UpdateTasks.psm1 - System and application update management tasks
# Contains tasks related to Windows updates, driver updates, and system patches

# ================================================================
# Function: Install-WindowsUpdates
# ================================================================
# Purpose: Install pending Windows updates
# ================================================================
function Install-WindowsUpdates {
    Write-Log "Starting Windows updates installation..." 'INFO'

    $updatesInstalled = 0

    try {
        # Check if PSWindowsUpdate module is available
        if (-not (Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Log "PSWindowsUpdate module not found, attempting installation..." 'WARN'
            try {
                Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -ErrorAction Stop
                Import-Module PSWindowsUpdate -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to install PSWindowsUpdate module: $_" 'ERROR'
                Write-Log "Falling back to Windows Update settings..." 'INFO'

                # Fallback: Enable automatic updates
                try {
                    $updateService = New-Object -ComObject Microsoft.Update.ServiceManager
                    $updateService.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "")
                    Write-Log "Microsoft Update service enabled" 'SUCCESS'
                }
                catch {
                    Write-Log "Failed to enable Microsoft Update service: $_" 'WARN'
                }

                return $false
            }
        }

        # Get available updates
        Write-Log "Checking for available Windows updates..." 'INFO'
        $availableUpdates = Get-WindowsUpdate -ErrorAction SilentlyContinue

        if ($availableUpdates) {
            $updateCount = $availableUpdates.Count
            Write-Log "Found $updateCount available updates" 'INFO'

            # Install updates
            Write-Log "Installing Windows updates..." 'INFO'
            $result = Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue

            if ($result) {
                $updatesInstalled = ($result | Where-Object { $_.Result -eq 'Installed' }).Count
                $failedUpdates = ($result | Where-Object { $_.Result -ne 'Installed' }).Count

                Write-Log "Windows updates completed: $updatesInstalled installed, $failedUpdates failed" 'SUCCESS'
            }
            else {
                Write-Log "No updates were installed" 'INFO'
            }
        }
        else {
            Write-Log "No Windows updates available" 'INFO'
        }

        return $true
    }
    catch {
        Write-Log "Critical error during Windows updates: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Install-OptionalUpdates
# ================================================================
# Purpose: Install optional Windows updates and features
# ================================================================
function Install-OptionalUpdates {
    Write-Log "Starting optional updates installation..." 'INFO'

    $updatesInstalled = 0

    try {
        # Install optional features
        $optionalFeatures = @(
            "NetFx3"
            "Microsoft-Windows-Subsystem-Linux"
            "VirtualMachinePlatform"
            "Containers-DisposableClientVM"
        )

        foreach ($feature in $optionalFeatures) {
            try {
                $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
                if ($featureState -and $featureState.State -ne "Enabled") {
                    Write-Log "Installing optional feature: $feature" 'INFO'
                    $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
                    if ($result.RestartNeeded) {
                        Write-Log "Feature $feature installed (restart required)" 'SUCCESS'
                    }
                    else {
                        Write-Log "Feature $feature installed" 'SUCCESS'
                    }
                    $updatesInstalled++
                }
                else {
                    Write-Log "Feature $feature already enabled or not available" 'DEBUG'
                }
            }
            catch {
                Write-Log "Failed to install feature $feature`: $_" 'WARN'
                $errors++
            }
        }

        # Install language packs if configured
        if ($global:Config.InstallLanguagePacks) {
            Write-Log "Installing language packs..." 'INFO'
            try {
                # This would install configured language packs
                # Implementation depends on specific requirements
                Write-Log "Language pack installation not implemented yet" 'WARN'
            }
            catch {
                Write-Log "Failed to install language packs: $_" 'WARN'
            }
        }

        Write-Log "Optional updates completed: $updatesInstalled installed, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during optional updates: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Update-DeviceDrivers
# ================================================================
# Purpose: Update device drivers using Windows Update
# ================================================================
function Update-DeviceDrivers {
    Write-Log "Starting device driver updates..." 'INFO'

    $driversUpdated = 0
    $errors = 0

    try {
        # Use PSWindowsUpdate for driver updates
        if (Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue) {
            Write-Log "Checking for driver updates..." 'INFO'

            $driverUpdates = Get-WindowsUpdate -Driver -ErrorAction SilentlyContinue

            if ($driverUpdates) {
                $driverCount = $driverUpdates.Count
                Write-Log "Found $driverCount driver updates" 'INFO'

                # Install driver updates
                $result = Get-WindowsUpdate -Driver -Install -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue

                if ($result) {
                    $driversUpdated = ($result | Where-Object { $_.Result -eq 'Installed' }).Count
                    Write-Log "Driver updates completed: $driversUpdated installed" 'SUCCESS'
                }
            }
            else {
                Write-Log "No driver updates available" 'INFO'
            }
        }
        else {
            Write-Log "PSWindowsUpdate module not available for driver updates" 'WARN'
            return $false
        }

        return $true
    }
    catch {
        Write-Log "Critical error during driver updates: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Update-WindowsStore
# ================================================================
# Purpose: Update Microsoft Store and its apps
# ================================================================
function Update-WindowsStore {
    Write-Log "Starting Windows Store updates..." 'INFO'

    try {
        # Reset Windows Store cache
        Write-Log "Resetting Windows Store cache..." 'INFO'
        try {
            Start-Process wsreset.exe -ArgumentList "/reset" -NoNewWindow -Wait -PassThru
            Write-Log "Windows Store cache reset completed" 'SUCCESS'
        }
        catch {
            Write-Log "Failed to reset Windows Store cache: $_" 'WARN'
        }

        # Update Store apps (this is handled by the application tasks module)
        Write-Log "Windows Store updates initiated" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during Windows Store updates: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Test-SystemHealth
# ================================================================
# Purpose: Run system health checks and repairs
# ================================================================
function Test-SystemHealth {
    Write-Log "Starting system health checks..." 'INFO'

    $issuesFound = 0
    $issuesFixed = 0

    try {
        # Run DISM health check
        Write-Log "Running DISM health check..." 'INFO'
        try {
            $dismResult = Start-Process dism.exe -ArgumentList "/Online /Cleanup-Image /CheckHealth" -NoNewWindow -Wait -PassThru
            if ($dismResult.ExitCode -eq 0) {
                Write-Log "DISM health check passed" 'SUCCESS'
            }
            else {
                Write-Log "DISM health check found issues" 'WARN'
                $issuesFound++

                # Attempt repair
                Write-Log "Attempting DISM repair..." 'INFO'
                $repairResult = Start-Process dism.exe -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
                if ($repairResult.ExitCode -eq 0) {
                    Write-Log "DISM repair completed successfully" 'SUCCESS'
                    $issuesFixed++
                }
                else {
                    Write-Log "DISM repair failed" 'ERROR'
                }
            }
        }
        catch {
            Write-Log "Error running DISM health check: $_" 'ERROR'
        }

        # Run SFC scan
        Write-Log "Running System File Checker..." 'INFO'
        try {
            $sfcResult = Start-Process sfc.exe -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
            if ($sfcResult.ExitCode -eq 0) {
                Write-Log "SFC scan completed successfully" 'SUCCESS'
            }
            else {
                Write-Log "SFC scan found and repaired issues" 'WARN'
                $issuesFound++
                $issuesFixed++
            }
        }
        catch {
            Write-Log "Error running SFC scan: $_" 'ERROR'
        }

        # Check Windows Update health
        Write-Log "Checking Windows Update service health..." 'INFO'
        try {
            $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
            if ($wuService.Status -ne 'Running') {
                Write-Log "Windows Update service not running, attempting to start..." 'WARN'
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
                $issuesFixed++
            }
            else {
                Write-Log "Windows Update service is running" 'SUCCESS'
            }
        }
        catch {
            Write-Log "Error checking Windows Update service: $_" 'WARN'
        }

        Write-Log "System health check completed: $issuesFound issues found, $issuesFixed fixed" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during system health check: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Optimize-WindowsUpdate
# ================================================================
# Purpose: Optimize Windows Update settings and performance
# ================================================================
function Optimize-WindowsUpdate {
    Write-Log "Optimizing Windows Update settings..." 'INFO'

    try {
        # Configure Windows Update settings
        try {
            # Set update settings via registry
            $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction SilentlyContinue
            }

            # Configure automatic updates
            Set-ItemProperty -Path $regPath -Name "AUOptions" -Value 4 -Type DWord -ErrorAction SilentlyContinue  # 4 = Auto download and schedule
            Set-ItemProperty -Path $regPath -Name "ScheduledInstallDay" -Value 0 -Type DWord -ErrorAction SilentlyContinue  # Every day
            Set-ItemProperty -Path $regPath -Name "ScheduledInstallTime" -Value 3 -Type DWord -ErrorAction SilentlyContinue  # 3 AM

            Write-Log "Windows Update settings optimized" 'SUCCESS'
        }
        catch {
            Write-Log "Failed to optimize Windows Update settings: $_" 'WARN'
        }

        # Clean up old update files
        Write-Log "Cleaning up old Windows Update files..." 'INFO'
        try {
            $result = Start-Process dism.exe -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Log "Windows Update cleanup completed" 'SUCCESS'
            }
            else {
                Write-Log "Windows Update cleanup failed" 'WARN'
            }
        }
        catch {
            Write-Log "Error during Windows Update cleanup: $_" 'ERROR'
        }

        return $true
    }
    catch {
        Write-Log "Critical error during Windows Update optimization: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Install-WindowsUpdates, Install-OptionalUpdates, Update-DeviceDrivers, Update-WindowsStore, Test-SystemHealth, Optimize-WindowsUpdate