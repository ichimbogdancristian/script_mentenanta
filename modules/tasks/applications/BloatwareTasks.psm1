# BloatwareTasks.psm1 - Bloatware removal tasks
# Contains tasks related to removing unwanted bloatware applications

# ================================================================
# Function: Get-BloatwareList
# ================================================================
# Purpose: Load bloatware definitions from external configuration file
# ================================================================
function Get-BloatwareList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\..\config\BloatwareList.psd1")
    )

    try {
        if (Test-Path $ConfigPath) {
            $bloatwareConfig = Import-PowerShellDataFile -Path $ConfigPath
            Write-Log "Loaded bloatware list from $ConfigPath" 'INFO'

            # Combine all bloatware categories into a single list
            $allBloatware = @()
            foreach ($category in $bloatwareConfig.Keys) {
                if ($bloatwareConfig[$category] -and $bloatwareConfig[$category].Count -gt 0) {
                    $allBloatware += $bloatwareConfig[$category]
                }
            }

            # Add custom bloatware from config if available
            if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
                $allBloatware += $global:Config.CustomBloatwareList
                Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries" 'INFO'
            }

            return $allBloatware | Select-Object -Unique
        }
        else {
            Write-Log "Bloatware configuration file not found at $ConfigPath. Please ensure BloatwareList.psd1 exists in the config directory." 'ERROR'
            throw "BloatwareList.psd1 configuration file is required but not found at $ConfigPath"
        }
    }
    catch {
        Write-Log "Failed to load bloatware list: $_" 'ERROR'
        return @()
    }
}

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
        # Get bloatware list from external configuration
        $bloatwareApps = Get-BloatwareList

        if ($bloatwareApps.Count -eq 0) {
            Write-Log "No bloatware applications defined for removal" 'WARN'
            return $false
        }

        Write-Log "Found $($bloatwareApps.Count) bloatware applications to check" 'INFO'

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

# Export functions
Export-ModuleMember -Function Remove-Bloatware, Get-BloatwareList