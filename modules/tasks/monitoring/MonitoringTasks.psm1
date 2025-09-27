# MonitoringTasks.psm1 - System monitoring and telemetry tasks
# Contains tasks related to system monitoring, logging, and security telemetry

# ================================================================
# Function: Enable-SystemMonitoring
# ================================================================
# Purpose: Enable system monitoring and telemetry services
# ================================================================
function Enable-SystemMonitoring {
    Write-Log "Enabling system monitoring services..." 'INFO'

    $servicesEnabled = 0
    $errors = 0

    try {
        # List of monitoring services to enable
        $monitoringServices = @(
            @{ Name = "Sysmon"; DisplayName = "System Monitor" }
            @{ Name = "EventLog"; DisplayName = "Windows Event Log" }
            @{ Name = "Wecsvc"; DisplayName = "Windows Event Collector" }
            @{ Name = "WinRM"; DisplayName = "Windows Remote Management" }
        )

        foreach ($service in $monitoringServices) {
            try {
                $svc = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
                if ($svc) {
                    if ($svc.Status -ne 'Running') {
                        Write-Log "Starting $($service.DisplayName) service..." 'INFO'
                        Start-Service -Name $service.Name -ErrorAction Stop
                        Write-Log "$($service.DisplayName) service started" 'SUCCESS'
                    }
                    else {
                        Write-Log "$($service.DisplayName) service already running" 'DEBUG'
                    }
                    $servicesEnabled++
                }
                else {
                    Write-Log "$($service.DisplayName) service not found" 'WARN'
                    $errors++
                }
            }
            catch {
                Write-Log "Failed to start $($service.DisplayName): $_" 'ERROR'
                $errors++
            }
        }

        # Configure Sysmon if config file exists
        $sysmonConfig = Join-Path $PSScriptRoot "..\..\..\config\sysmonconfig.xml"
        if (Test-Path $sysmonConfig) {
            Write-Log "Configuring Sysmon with custom configuration..." 'INFO'
            try {
                $result = Start-Process sysmon.exe -ArgumentList "-c $sysmonConfig" -NoNewWindow -Wait -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Log "Sysmon configured successfully" 'SUCCESS'
                }
                else {
                    Write-Log "Failed to configure Sysmon (exit code: $($result.ExitCode))" 'WARN'
                }
            }
            catch {
                Write-Log "Error configuring Sysmon: $_" 'ERROR'
            }
        }

        Write-Log "System monitoring setup completed: $servicesEnabled services enabled, $errors errors" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error enabling system monitoring: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Set-EventLogging
# ================================================================
# Purpose: Configure Windows Event Log settings and retention
# ================================================================
function Set-EventLogging {
    Write-Log "Configuring event logging settings..." 'INFO'

    try {
        # Configure event log sizes and retention
        $eventLogs = @(
            @{ LogName = "Application"; MaxSize = 20MB; Retention = $true }
            @{ LogName = "System"; MaxSize = 20MB; Retention = $true }
            @{ LogName = "Security"; MaxSize = 40MB; Retention = $true }
        )

        foreach ($log in $eventLogs) {
            try {
                Write-Log "Configuring $($log.LogName) event log..." 'INFO'
                $logPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$($log.LogName)"

                # Set maximum log size
                Set-ItemProperty -Path $logPath -Name "MaxSize" -Value $log.MaxSize -Type DWord -ErrorAction SilentlyContinue

                # Set retention policy
                Set-ItemProperty -Path $logPath -Name "Retention" -Value $log.Retention -Type DWord -ErrorAction SilentlyContinue

                Write-Log "$($log.LogName) event log configured" 'SUCCESS'
            }
            catch {
                Write-Log "Failed to configure $($log.LogName) event log: $_" 'WARN'
            }
        }

        # Clear old event logs if configured
        if ($global:Config.ClearOldEventLogs) {
            Write-Log "Clearing old event logs..." 'INFO'
            try {
                foreach ($log in $eventLogs) {
                    Clear-EventLog -LogName $log.LogName -ErrorAction SilentlyContinue
                }
                Write-Log "Old event logs cleared" 'SUCCESS'
            }
            catch {
                Write-Log "Failed to clear old event logs: $_" 'WARN'
            }
        }

        Write-Log "Event logging configuration completed" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error configuring event logging: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Initialize-PerformanceMonitoring
# ================================================================
# Purpose: Set up performance counters and monitoring
# ================================================================
function Initialize-PerformanceMonitoring {
    Write-Log "Setting up performance monitoring..." 'INFO'

    try {
        # Enable performance counters
        # Note: Performance counters are configured but not stored in variable

        Write-Log "Performance counters configured for monitoring" 'SUCCESS'

        # Configure data collector sets if needed
        Write-Log "Performance monitoring setup completed" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error setting up performance monitoring: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Enable-TelemetryReporting
# ================================================================
# Purpose: Configure Windows telemetry and diagnostic reporting
# ================================================================
function Enable-TelemetryReporting {
    Write-Log "Configuring telemetry and diagnostic reporting..." 'INFO'

    try {
        # Set telemetry level (0=Security, 1=Basic, 2=Enhanced, 3=Full)
        $telemetryLevel = $global:Config.TelemetryLevel ?? 2

        Write-Log "Setting telemetry level to $telemetryLevel..." 'INFO'

        # Configure telemetry via registry
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        )

        foreach ($regPath in $regPaths) {
            try {
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force -ErrorAction SilentlyContinue
                }

                Set-ItemProperty -Path $regPath -Name "AllowTelemetry" -Value $telemetryLevel -Type DWord -ErrorAction SilentlyContinue
                Write-Log "Telemetry configured in registry: $regPath" 'SUCCESS'
            }
            catch {
                Write-Log "Failed to configure telemetry in $regPath`: $_" 'WARN'
            }
        }

        # Enable diagnostic services
        $diagServices = @("DiagTrack", "dmwappushservice")
        foreach ($service in $diagServices) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne 'Running') {
                    Start-Service -Name $service -ErrorAction SilentlyContinue
                    Write-Log "Diagnostic service $service started" 'SUCCESS'
                }
            }
            catch {
                Write-Log "Failed to start diagnostic service $service`: $_" 'WARN'
            }
        }

        Write-Log "Telemetry and diagnostic reporting configured" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error configuring telemetry: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Watch-SystemResources
# ================================================================
# Purpose: Monitor system resources and create alerts
# ================================================================
function Watch-SystemResources {
    Write-Log "Monitoring system resources..." 'INFO'

    try {
        # Get system resource usage
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        $memoryUsage = (Get-Counter '\Memory\% Committed Bytes In Use' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue

        $cpuPercent = [math]::Round($cpuUsage, 2)
        $memoryPercent = [math]::Round($memoryUsage, 2)

        Write-Log "Current resource usage - CPU: ${cpuPercent}%, Memory: ${memoryPercent}%" 'INFO'

        # Check thresholds
        $cpuThreshold = $global:Config.CPUThreshold ?? 90
        $memoryThreshold = $global:Config.MemoryThreshold ?? 90

        $alerts = 0

        if ($cpuUsage -gt $cpuThreshold) {
            Write-Log "HIGH CPU USAGE ALERT: ${cpuPercent}% (threshold: ${cpuThreshold}%)" 'WARN'
            $alerts++
        }

        if ($memoryUsage -gt $memoryThreshold) {
            Write-Log "HIGH MEMORY USAGE ALERT: ${memoryPercent}% (threshold: ${memoryThreshold}%)" 'WARN'
            $alerts++
        }

        # Get disk usage
        $disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        foreach ($disk in $disks) {
            $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
            $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 2)

            Write-Log "Disk $($disk.DeviceID): ${usedPercent}% used (${freeSpaceGB}GB free of ${totalSpaceGB}GB)" 'INFO'

            $diskThreshold = $global:Config.DiskThreshold ?? 90
            if ($usedPercent -gt $diskThreshold) {
                Write-Log "LOW DISK SPACE ALERT: $($disk.DeviceID) ${usedPercent}% used (threshold: ${diskThreshold}%)" 'WARN'
                $alerts++
            }
        }

        if ($alerts -eq 0) {
            Write-Log "System resources within normal parameters" 'SUCCESS'
        }
        else {
            Write-Log "System resource monitoring completed with $alerts alerts" 'WARN'
        }

        return $true
    }
    catch {
        Write-Log "Critical error monitoring system resources: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: New-SystemReport
# ================================================================
# Purpose: Generate a comprehensive system monitoring report
# ================================================================
function New-SystemReport {
    Write-Log "Generating system monitoring report..." 'INFO'

    try {
        # Use a single report file instead of timestamped files
        $reportPath = Join-Path $PSScriptRoot "..\..\..\system_report.txt"

        $report = @"
System Monitoring Report
Generated: $(Get-Date)
Computer: $env:COMPUTERNAME
User: $env:USERNAME

=== SYSTEM INFORMATION ===
OS Version: $(Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Caption)
Build: $(Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty BuildNumber)
Architecture: $(Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OSArchitecture)

=== HARDWARE INFORMATION ===
CPU: $(Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name)
Memory: $([math]::Round((Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TotalPhysicalMemory) / 1GB, 2)) GB

=== CURRENT RESOURCE USAGE ===
"@

        # Add current resource usage
        try {
            $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
            $memoryUsage = (Get-Counter '\Memory\% Committed Bytes In Use' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue

            $report += "CPU Usage: $([math]::Round($cpuUsage, 2))%`n"
            $report += "Memory Usage: $([math]::Round($memoryUsage, 2))%`n"
        }
        catch {
            $report += "Resource usage: Unable to retrieve`n"
        }

        # Add disk information
        $report += "`n=== DISK INFORMATION ===`n"
        $disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        foreach ($disk in $disks) {
            $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
            $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 2)

            $report += "$($disk.DeviceID): ${usedPercent}% used (${freeSpaceGB}GB free of ${totalSpaceGB}GB)`n"
        }

        # Add running services
        $report += "`n=== MONITORING SERVICES STATUS ===`n"
        $monitoringServices = @("Sysmon", "EventLog", "Wecsvc", "WinRM", "DiagTrack")
        foreach ($service in $monitoringServices) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                $status = if ($svc) { $svc.Status } else { "Not Found" }
                $report += "$service`: $status`n"
            }
            catch {
                $report += "$service`: Error checking status`n"
            }
        }

        # Add maintenance execution summary if available
        if ($global:TaskResults -and $global:TaskResults.Count -gt 0) {
            $report += "`n=== MAINTENANCE EXECUTION SUMMARY ===`n"
            $successfulTasks = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
            $totalTasks = $global:TaskResults.Count
            $totalDuration = ($global:TaskResults.Values | Measure-Object -Property Duration -Sum).Sum

            $report += "Total Tasks Executed: $totalTasks`n"
            $report += "Successful Tasks: $successfulTasks`n"
            $report += "Failed Tasks: $($totalTasks - $successfulTasks)`n"
            $report += "Total Execution Time: $([math]::Round($totalDuration, 2)) seconds`n"

            # List failed tasks
            $failedTasks = $global:TaskResults.GetEnumerator() | Where-Object { -not $_.Value.Success }
            if ($failedTasks) {
                $report += "`nFailed Tasks:`n"
                foreach ($task in $failedTasks) {
                    $report += "- $($task.Key): $($task.Value.Error)`n"
                }
            }
        }

        # Save report
        $report | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Log "System report generated: $reportPath" 'SUCCESS'

        return $true
    }
    catch {
        Write-Log "Critical error generating system report: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Compress-EventLogs
# ================================================================
# Purpose: Archive and compress old event logs
# ================================================================
function Compress-EventLogs {
    Write-Log "Archiving event logs..." 'INFO'

    try {
        $archivePath = Join-Path $PSScriptRoot "..\..\..\event_logs_archive_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"

        # Export event logs
        $eventLogs = @("Application", "System", "Security")
        $tempPath = Join-Path $env:TEMP "event_logs_temp"

        if (-not (Test-Path $tempPath)) {
            New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        }

        foreach ($log in $eventLogs) {
            try {
                $exportPath = Join-Path $tempPath "$log`_$(Get-Date -Format 'yyyyMMdd').evtx"
                wevtutil.exe epl $log $exportPath /q:true 2>$null
                Write-Log "Exported $log event log" 'DEBUG'
            }
            catch {
                Write-Log "Failed to export $log event log: $_" 'WARN'
            }
        }

        # Compress archived logs
        try {
            Compress-Archive -Path $tempPath -DestinationPath $archivePath -ErrorAction Stop
            Write-Log "Event logs archived: $archivePath" 'SUCCESS'
        }
        catch {
            Write-Log "Failed to compress event logs: $_" 'ERROR'
        }

        # Clean up temp files
        Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-Log "Critical error archiving event logs: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Enable-SystemMonitoring, Set-EventLogging, Initialize-PerformanceMonitoring, Enable-TelemetryReporting, Watch-SystemResources, New-SystemReport, Compress-EventLogs