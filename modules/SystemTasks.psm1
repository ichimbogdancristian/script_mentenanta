# SystemTasks Module
# Contains individual maintenance task implementations

function Invoke-SystemRestorePoint {
    <#
    .SYNOPSIS
    Creates a system restore point.
    
    .PARAMETER TaskSettings
    Configuration settings for this task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskSettings
    )
    
    try {
        Write-LogMessage -Level "Info" -Message "Creating system restore point..."
        
        # Check if System Restore is enabled
        $restoreStatus = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($null -eq $restoreStatus) {
            Write-LogMessage -Level "Warning" -Message "System Restore is not enabled. Enabling it now..."
            Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
        }
        
        # Create restore point
        $restorePointName = "Maintenance Script - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Checkpoint-Computer -Description $restorePointName -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        
        Write-LogMessage -Level "Info" -Message "System restore point created successfully: $restorePointName"
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed to create system restore point" -Exception $_.Exception
        return $false
    }
}

function Invoke-DefenderScan {
    <#
    .SYNOPSIS
    Runs Windows Defender scan.
    
    .PARAMETER TaskSettings
    Configuration settings for this task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskSettings
    )
    
    try {
        $scanType = if ($TaskSettings.scanType) { $TaskSettings.scanType } else { "Quick" }
        Write-LogMessage -Level "Info" -Message "Starting Windows Defender $scanType scan..."
        
        Start-MpScan -ScanType $scanType -ErrorAction Stop
        Write-LogMessage -Level "Info" -Message "Windows Defender scan completed successfully"
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Windows Defender scan failed" -Exception $_.Exception
        return $false
    }
}

function Invoke-DiskCleanup {
    <#
    .SYNOPSIS
    Performs disk cleanup operations.
    
    .PARAMETER TaskSettings
    Configuration settings for this task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskSettings
    )
    
    try {
        Write-LogMessage -Level "Info" -Message "Starting disk cleanup..."
        
        # Clean temporary files
        if ($TaskSettings.includeTempFiles) {
            $tempPath = $env:TEMP
            Write-LogMessage -Level "Info" -Message "Cleaning temporary files from: $tempPath"
            Get-ChildItem -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        # Clean system cache
        if ($TaskSettings.includeSystemCache) {
            Write-LogMessage -Level "Info" -Message "Cleaning Windows temporary files..."
            $systemTemp = Join-Path $env:SystemRoot "Temp"
            Get-ChildItem -Path $systemTemp -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        # Run built-in disk cleanup
        Write-LogMessage -Level "Info" -Message "Running Windows Disk Cleanup utility..."
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -WindowStyle Hidden -ErrorAction Stop
        
        Write-LogMessage -Level "Info" -Message "Disk cleanup completed successfully"
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Disk cleanup failed" -Exception $_.Exception
        return $false
    }
}

function Invoke-SystemFileCheck {
    <#
    .SYNOPSIS
    Runs SFC and DISM system file checks.
    
    .PARAMETER TaskSettings
    Configuration settings for this task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskSettings
    )
    
    try {
        $success = $true
        
        # Run SFC scan
        if ($TaskSettings.runSfc) {
            Write-LogMessage -Level "Info" -Message "Running SFC scan..."
            $sfcResult = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -WindowStyle Hidden
            if ($sfcResult.ExitCode -eq 0) {
                Write-LogMessage -Level "Info" -Message "SFC scan completed successfully"
            } else {
                Write-LogMessage -Level "Warning" -Message "SFC scan completed with exit code: $($sfcResult.ExitCode)"
                $success = $false
            }
        }
        
        # Run DISM check
        if ($TaskSettings.runDism) {
            Write-LogMessage -Level "Info" -Message "Running DISM health check..."
            $dismResult = Start-Process -FilePath "dism.exe" -ArgumentList "/online", "/cleanup-image", "/restorehealth" -Wait -PassThru -WindowStyle Hidden
            if ($dismResult.ExitCode -eq 0) {
                Write-LogMessage -Level "Info" -Message "DISM health check completed successfully"
            } else {
                Write-LogMessage -Level "Warning" -Message "DISM health check completed with exit code: $($dismResult.ExitCode)"
                $success = $false
            }
        }
        
        return $success
    }
    catch {
        Write-LogMessage -Level "Error" -Message "System file check failed" -Exception $_.Exception
        return $false
    }
}

function Invoke-WindowsUpdates {
    <#
    .SYNOPSIS
    Installs Windows Updates.
    
    .PARAMETER TaskSettings
    Configuration settings for this task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskSettings
    )
    
    try {
        Write-LogMessage -Level "Info" -Message "Checking for Windows Updates..."
        
        # Check if PSWindowsUpdate module is available
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-LogMessage -Level "Info" -Message "Installing PSWindowsUpdate module..."
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        }
        
        Import-Module PSWindowsUpdate -ErrorAction Stop
        
        # Get available updates
        $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot
        
        if ($updates.Count -eq 0) {
            Write-LogMessage -Level "Info" -Message "No updates available"
            return $true
        }
        
        Write-LogMessage -Level "Info" -Message "Found $($updates.Count) updates. Installing..."
        
        # Install updates
        $installResult = Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
        
        Write-LogMessage -Level "Info" -Message "Windows Updates installation completed"
        
        if ($TaskSettings.rebootIfRequired -and $installResult.RebootRequired) {
            Write-LogMessage -Level "Warning" -Message "System reboot required to complete updates"
        }
        
        return $true
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Windows Updates installation failed" -Exception $_.Exception
        return $false
    }
}

Export-ModuleMember -Function Invoke-SystemRestorePoint, Invoke-DefenderScan, Invoke-DiskCleanup, Invoke-SystemFileCheck, Invoke-WindowsUpdates
