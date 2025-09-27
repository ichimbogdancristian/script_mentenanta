# EssentialApps.psm1 - Essential application installation tasks
# Contains tasks related to installing essential applications

# ================================================================
# Function: Get-EssentialAppsList
# ================================================================
# Purpose: Load essential applications definitions from external configuration file
# ================================================================
function Get-EssentialAppsList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\..\config\EssentialAppsList.psd1")
    )

    try {
        if (Test-Path $ConfigPath) {
            $essentialConfig = Import-PowerShellDataFile -Path $ConfigPath
            Write-Log "Loaded essential apps list from $ConfigPath" 'INFO'

            # Combine all essential apps categories into a single list
            $allEssentialApps = @()
            foreach ($category in $essentialConfig.Keys) {
                if ($essentialConfig[$category] -and $essentialConfig[$category].Count -gt 0) {
                    $allEssentialApps += $essentialConfig[$category]
                }
            }

            # Add custom essential apps from config if available
            if ($global:Config.CustomEssentialApps -and $global:Config.CustomEssentialApps.Count -gt 0) {
                $allEssentialApps += $global:Config.CustomEssentialApps
                Write-Log "Added $($global:Config.CustomEssentialApps.Count) custom essential apps" 'INFO'
            }

            return $allEssentialApps | Select-Object -Unique
        }
        else {
            Write-Log "Essential apps configuration file not found at $ConfigPath. Please ensure EssentialAppsList.psd1 exists in the config directory." 'ERROR'
            throw "EssentialAppsList.psd1 configuration file is required but not found at $ConfigPath"
        }
    }
    catch {
        Write-Log "Failed to load essential apps list: $_" 'ERROR'
        return @()
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
        # Get list of essential apps from external configuration
        $essentialAppsList = Get-EssentialAppsList

        if ($essentialAppsList.Count -eq 0) {
            Write-Log "No essential applications defined for installation" 'WARN'
            return $false
        }

        Write-Log "Found $($essentialAppsList.Count) essential applications to check" 'INFO'

        # Process each essential app
        foreach ($app in $essentialAppsList) {
            # Handle different app formats (hashtable with Winget/Choco properties vs simple string)
            if ($app -is [hashtable] -and $app.Winget) {
                # Use Winget ID
                $appId = $app.Winget
                $appName = $app.Name
            }
            elseif ($app -is [hashtable] -and $app.Id) {
                # Legacy format from config
                $appId = $app.Id
                $appName = $app.Name
            }
            elseif ($app -is [string]) {
                # Simple string format
                $appId = $app
                $appName = $app
            }
            else {
                Write-Log "Skipping invalid app entry: $app" 'WARN'
                continue
            }

            # Try Winget first
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    Write-Log "Installing $appName via Winget..." 'INFO'
                    $result = Start-Process winget -ArgumentList "install --id $appId --accept-source-agreements --accept-package-agreements -e -h" -NoNewWindow -Wait -PassThru

                    if ($result.ExitCode -eq 0) {
                        $installedCount++
                        Write-Log "Successfully installed $appName" 'SUCCESS'
                        continue
                    }
                    else {
                        Write-Log "Failed to install $appName via Winget (exit code: $($result.ExitCode))" 'WARN'
                    }
                }
                catch {
                    Write-Log "Error installing $appName via Winget`: $_" 'ERROR'
                }
            }

            # Try Chocolatey as fallback
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                try {
                    Write-Log "Installing $appName via Chocolatey..." 'INFO'
                    $result = Start-Process choco -ArgumentList "install $appId -y" -NoNewWindow -Wait -PassThru

                    if ($result.ExitCode -eq 0) {
                        $installedCount++
                        Write-Log "Successfully installed $appName via Chocolatey" 'SUCCESS'
                    }
                    else {
                        Write-Log "Failed to install $appName via Chocolatey (exit code: $($result.ExitCode))" 'WARN'
                        $errors++
                    }
                }
                catch {
                    Write-Log "Error installing $appName via Chocolatey`: $_" 'ERROR'
                    $errors++
                }
            }
            else {
                Write-Log "No package manager available for $appName installation" 'WARN'
                $errors++
            }
        }

        Write-Log "Essential apps installation completed: $installedCount installed, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during essential apps installation: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Install-EssentialApps, Get-EssentialAppsList