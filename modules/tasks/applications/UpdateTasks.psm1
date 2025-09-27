# UpdateTasks.psm1 - Application update tasks
# Contains tasks related to updating installed applications

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

# Export functions
Export-ModuleMember -Function Update-InstalledApplications