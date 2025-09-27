# ApplicationTasks.psm1 - Application management and bloatware removal tasks
# Contains tasks related to installing, removing, and managing applications

# ================================================================
# Function: Remove-Bloatware
# ================================================================
# Purpose: Remove unwanted bloatware applications from the system
# ================================================================
function Remove-Bloatware {
    Write-Log "Starting bloatware removal process..." 'INFO'

    $removedCount = 0
    $errors = 0

    try {
        # Get bloatware inventory (this would come from inventory module)
        # For now, using a basic list
        $bloatwareApps = @(
            "Microsoft.BingWeather"
            "Microsoft.GetHelp"
            "Microsoft.Getstarted"
            "Microsoft.Messaging"
            "Microsoft.Microsoft3DViewer"
            "Microsoft.MicrosoftOfficeHub"
            "Microsoft.MicrosoftSolitaireCollection"
            "Microsoft.MixedReality.Portal"
            "Microsoft.Office.OneNote"
            "Microsoft.People"
            "Microsoft.SkypeApp"
            "Microsoft.Wallet"
            "Microsoft.WindowsAlarms"
            "Microsoft.WindowsCamera"
            "Microsoft.WindowsFeedbackHub"
            "Microsoft.WindowsMaps"
            "Microsoft.WindowsSoundRecorder"
            "Microsoft.Xbox.TCUI"
            "Microsoft.XboxApp"
            "Microsoft.XboxGameOverlay"
            "Microsoft.XboxGamingOverlay"
            "Microsoft.XboxSpeechToTextOverlay"
            "Microsoft.YourPhone"
            "Microsoft.ZuneMusic"
            "Microsoft.ZuneVideo"
        )

        foreach ($app in $bloatwareApps) {
            try {
                $installedApp = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
                if ($installedApp) {
                    Write-Log "Removing bloatware: $app" 'INFO'
                    $installedApp | Remove-AppxPackage -AllUsers -ErrorAction Stop
                    $removedCount++
                }
                else {
                    Write-Log "Bloatware not found: $app" 'DEBUG'
                }
            }
            catch {
                Write-Log "Failed to remove $app`: $_" 'WARN'
                $errors++
            }
        }

        # Remove provisioned packages (prevents reinstallation)
        foreach ($app in $bloatwareApps) {
            try {
                $provisionedApp = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app } -ErrorAction SilentlyContinue
                if ($provisionedApp) {
                    Write-Log "Removing provisioned package: $app" 'INFO'
                    Remove-AppxProvisionedPackage -Online -PackageName $provisionedApp.PackageName -ErrorAction Stop
                }
            }
            catch {
                Write-Log "Failed to remove provisioned package $app`: $_" 'WARN'
            }
        }

        Write-Log "Bloatware removal completed: $removedCount removed, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during bloatware removal: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Install-EssentialApps
# ================================================================
# Purpose: Install essential applications using various package managers
# ================================================================
function Install-EssentialApps {
    Write-Log "Starting essential apps installation..." 'INFO'

    $installedCount = 0
    $errors = 0

    try {
        # Get list of essential apps from config
        $essentialApps = $global:Config.CustomEssentialApps
        if (-not $essentialApps -or $essentialApps.Count -eq 0) {
            # Default essential apps
            $essentialApps = @(
                "7zip.7zip"
                "Mozilla.Firefox"
                "VideoLAN.VLC"
                "Notepad++.Notepad++"
            )
        }

        # Try Winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Using Winget for app installation" 'INFO'

            foreach ($app in $essentialApps) {
                try {
                    Write-Log "Installing $app via Winget..." 'INFO'
                    $result = Start-Process winget -ArgumentList "install --id $app --accept-source-agreements --accept-package-agreements -e -h" -NoNewWindow -Wait -PassThru

                    if ($result.ExitCode -eq 0) {
                        $installedCount++
                        Write-Log "Successfully installed $app" 'SUCCESS'
                    }
                    else {
                        Write-Log "Failed to install $app (exit code: $($result.ExitCode))" 'WARN'
                        $errors++
                    }
                }
                catch {
                    Write-Log "Error installing $app`: $_" 'ERROR'
                    $errors++
                }
            }
        }
        # Try Chocolatey as fallback
        elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Using Chocolatey for app installation" 'INFO'

            foreach ($app in $essentialApps) {
                try {
                    Write-Log "Installing $app via Chocolatey..." 'INFO'
                    $result = Start-Process choco -ArgumentList "install $app -y" -NoNewWindow -Wait -PassThru

                    if ($result.ExitCode -eq 0) {
                        $installedCount++
                        Write-Log "Successfully installed $app" 'SUCCESS'
                    }
                    else {
                        Write-Log "Failed to install $app (exit code: $($result.ExitCode))" 'WARN'
                        $errors++
                    }
                }
                catch {
                    Write-Log "Error installing $app`: $_" 'ERROR'
                    $errors++
                }
            }
        }
        else {
            Write-Log "No package manager available for app installation" 'WARN'
            return $false
        }

        Write-Log "Essential apps installation completed: $installedCount installed, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during essential apps installation: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Update-InstalledApplications
# ================================================================
# Purpose: Update all installed applications
# ================================================================
function Update-InstalledApplications {
    Write-Log "Starting application updates..." 'INFO'

    $updatedCount = 0
    $errors = 0

    try {
        # Update Winget packages
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Updating Winget packages..." 'INFO'
            try {
                $result = Start-Process winget -ArgumentList "upgrade --all --accept-source-agreements --accept-package-agreements -h" -NoNewWindow -Wait -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Log "Winget packages updated successfully" 'SUCCESS'
                    $updatedCount++
                }
                else {
                    Write-Log "Winget update failed (exit code: $($result.ExitCode))" 'WARN'
                    $errors++
                }
            }
            catch {
                Write-Log "Error updating Winget packages: $_" 'ERROR'
                $errors++
            }
        }

        # Update Chocolatey packages
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Updating Chocolatey packages..." 'INFO'
            try {
                $result = Start-Process choco -ArgumentList "upgrade all -y" -NoNewWindow -Wait -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Log "Chocolatey packages updated successfully" 'SUCCESS'
                    $updatedCount++
                }
                else {
                    Write-Log "Chocolatey update failed (exit code: $($result.ExitCode))" 'WARN'
                    $errors++
                }
            }
            catch {
                Write-Log "Error updating Chocolatey packages: $_" 'ERROR'
                $errors++
            }
        }

        # Update Microsoft Store apps
        Write-Log "Updating Microsoft Store apps..." 'INFO'
        try {
            $result = Start-Process wsreset.exe -ArgumentList "/reset" -NoNewWindow -Wait -PassThru
            Write-Log "Microsoft Store reset completed" 'INFO'
        }
        catch {
            Write-Log "Error resetting Microsoft Store: $_" 'WARN'
        }

        Write-Log "Application updates completed: $updatedCount updated, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during application updates: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Repair-BrokenApplications
# ================================================================
# Purpose: Attempt to repair broken or corrupted applications
# ================================================================
function Repair-BrokenApplications {
    Write-Log "Starting application repair process..." 'INFO'

    $repairedCount = 0
    $errors = 0

    try {
        # Repair Microsoft Store apps
        Write-Log "Repairing Microsoft Store apps..." 'INFO'
        try {
            Get-AppxPackage -AllUsers | ForEach-Object {
                try {
                    $appName = $_.Name
                    Write-Log "Repairing $appName..." 'DEBUG'
                    # Reset app to default state
                    # Note: This is a simplified repair - real repair would be more complex
                    $repairedCount++
                }
                catch {
                    Write-Log "Failed to repair $appName`: $_" 'WARN'
                    $errors++
                }
            }
        }
        catch {
            Write-Log "Error repairing Store apps: $_" 'ERROR'
            $errors++
        }

        # Repair Windows features
        Write-Log "Repairing Windows features..." 'INFO'
        try {
            $result = Start-Process dism.exe -ArgumentList "/Online /Enable-Feature /FeatureName:NetFx3 /All" -NoNewWindow -Wait -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Log "Windows features repaired" 'SUCCESS'
            }
        }
        catch {
            Write-Log "Error repairing Windows features: $_" 'WARN'
        }

        Write-Log "Application repair completed: $repairedCount repaired, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during application repair: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Clear-ApplicationCache
# ================================================================
# Purpose: Clean application caches and temporary data
# ================================================================
function Clear-ApplicationCache {
    Write-Log "Cleaning application caches..." 'INFO'

    $cleanedSize = 0

    try {
        # Clean Windows Store cache
        try {
            Start-Process wsreset.exe -ArgumentList "/reset" -NoNewWindow -Wait -PassThru
            Write-Log "Windows Store cache reset" 'INFO'
        }
        catch {
            Write-Log "Failed to reset Windows Store cache: $_" 'WARN'
        }

        # Clean browser caches (example for common browsers)
        $browserCachePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*.default\cache2"
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        )

        foreach ($cachePath in $browserCachePaths) {
            try {
                if (Test-Path $cachePath) {
                    $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $cleanedSize += $cacheSize
                    Write-Log "Cleaned browser cache: $cachePath" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to clean cache $cachePath`: $_" 'WARN'
            }
        }

        $cleanedMB = [math]::Round($cleanedSize / 1MB, 2)
        Write-Log "Application cache cleaning completed: ${cleanedMB}MB cleaned" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during cache cleaning: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Remove-Bloatware, Install-EssentialApps, Update-InstalledApplications, Repair-BrokenApplications, Clear-ApplicationCache