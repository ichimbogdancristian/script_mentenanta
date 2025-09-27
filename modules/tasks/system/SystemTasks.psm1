# SystemTasks.psm1 - System maintenance and health tasks
# Contains tasks related to system health, restore points, and system optimization

# ================================================================
# Function: Protect-SystemRestore
# ================================================================
# Purpose: Enable and configure System Restore protection
# ================================================================
function Protect-SystemRestore {
    Write-Log "Configuring System Restore protection..." 'INFO'

    try {
        # Enable System Restore for system drive
        $systemDrive = $env:SystemDrive
        $result = Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop

        # Create a restore point
        $restorePoint = Checkpoint-Computer -Description "Pre-Maintenance Restore Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop

        Write-Log "System Restore enabled and restore point created: $($restorePoint.Description)" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Failed to configure System Restore: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Optimize-SystemHealth
# ================================================================
# Purpose: Run system file checks and component repairs
# ================================================================
function Optimize-SystemHealth {
    Write-Log "Running system health optimization..." 'INFO'

    $results = @{
        DISM = $false
        SFC = $false
        Overall = $false
    }

    try {
        # Run DISM health check and repair
        Write-Log "Running DISM health check..." 'INFO'
        $dismResult = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth /Quiet" -NoNewWindow -Wait -PassThru

        if ($dismResult.ExitCode -eq 0) {
            $results.DISM = $true
            Write-Log "DISM health check completed successfully" 'SUCCESS'
        }
        else {
            Write-Log "DISM health check failed with exit code $($dismResult.ExitCode)" 'WARN'
        }

        # Run System File Checker
        Write-Log "Running System File Checker..." 'INFO'
        $sfcResult = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru

        if ($sfcResult.ExitCode -eq 0) {
            $results.SFC = $true
            Write-Log "System File Checker completed successfully" 'SUCCESS'
        }
        else {
            Write-Log "System File Checker failed with exit code $($sfcResult.ExitCode)" 'WARN'
        }

        $results.Overall = $results.DISM -and $results.SFC
        return $results.Overall
    }
    catch {
        Write-Log "System health optimization failed: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Check-PendingRestart
# ================================================================
# Purpose: Check for pending system restart requirements
# ================================================================
function Check-PendingRestart {
    Write-Log "Checking for pending restart..." 'INFO'

    $pendingRestart = $false
    $reasons = @()

    try {
        # Check Windows Update pending restart
        $wuau = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "RebootRequired" -ErrorAction SilentlyContinue
        if ($wuau) {
            $pendingRestart = $true
            $reasons += "Windows Update requires restart"
        }

        # Check Component Based Servicing
        $cbs = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RebootPending" -ErrorAction SilentlyContinue
        if ($cbs) {
            $pendingRestart = $true
            $reasons += "Component Based Servicing requires restart"
        }

        # Check pending file rename operations
        $pendingOps = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pendingOps) {
            $pendingRestart = $true
            $reasons += "Pending file operations require restart"
        }

        if ($pendingRestart) {
            Write-Log "Pending restart detected: $($reasons -join ', ')" 'WARN'
        }
        else {
            Write-Log "No pending restart required" 'INFO'
        }

        return -not $pendingRestart  # Return true if no restart needed
    }
    catch {
        Write-Log "Failed to check pending restart: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Clear-SystemTempFiles
# ================================================================
# Purpose: Clean up temporary files and folders
# ================================================================
function Clear-SystemTempFiles {
    Write-Log "Cleaning system temporary files..." 'INFO'

    $cleanedSize = 0
    $errors = 0

    try {
        # Clean Windows Temp folder
        $tempPaths = @(
            $env:TEMP
            "$env:SystemRoot\Temp"
            "$env:SystemRoot\Logs"
        )

        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                Write-Log "Cleaning $path..." 'INFO'
                try {
                    $files = Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue
                    foreach ($file in $files) {
                        try {
                            $fileSize = $file.Length
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            $cleanedSize += $fileSize
                        }
                        catch {
                            $errors++
                        }
                    }
                }
                catch {
                    Write-Log "Failed to clean $path`: $_" 'WARN'
                }
            }
        }

        # Clean Recycle Bin (requires admin)
        try {
            $recycleBin = (New-Object -ComObject Shell.Application).NameSpace(0xA)
            $recycleBin.Items() | ForEach-Object { $_.InvokeVerb("delete") }
            Write-Log "Recycle Bin emptied" 'INFO'
        }
        catch {
            Write-Log "Failed to empty Recycle Bin: $_" 'WARN'
        }

        $cleanedMB = [math]::Round($cleanedSize / 1MB, 2)
        Write-Log "Cleaned ${cleanedMB}MB of temporary files ($errors errors)" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Failed to clean temporary files: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Optimize-SystemPerformance
# ================================================================
# Purpose: Apply various system performance optimizations
# ================================================================
function Optimize-SystemPerformance {
    Write-Log "Applying system performance optimizations..." 'INFO'

    $optimizations = @()

    try {
        # Disable unnecessary services
        $servicesToDisable = @(
            "SysMain"  # Superfetch
            "WSearch"  # Windows Search (if not needed)
        )

        foreach ($service in $servicesToDisable) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') {
                    Stop-Service -Name $service -Force -ErrorAction Stop
                    Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                    $optimizations += "Disabled service: $service"
                }
            }
            catch {
                Write-Log "Failed to disable service $service`: $_" 'WARN'
            }
        }

        # Optimize visual effects
        try {
            $visualEffects = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -ErrorAction SilentlyContinue
            if (-not $visualEffects -or $visualEffects.VisualFXSetting -ne 2) {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Type DWord
                $optimizations += "Optimized visual effects for performance"
            }
        }
        catch {
            Write-Log "Failed to optimize visual effects: $_" 'WARN'
        }

        Write-Log "Applied $($optimizations.Count) performance optimizations" 'SUCCESS'
        foreach ($opt in $optimizations) {
            Write-Log "  - $opt" 'INFO'
        }

        return $true
    }
    catch {
        Write-Log "Failed to apply performance optimizations: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Protect-SystemRestore, Optimize-SystemHealth, Check-PendingRestart, Clear-SystemTempFiles, Optimize-SystemPerformance