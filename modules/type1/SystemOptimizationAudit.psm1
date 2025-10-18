#Requires -Version 7.0
# Module Dependencies:
#   - LoggingManager.psm1 (for structured logging)
#   - ConfigManager.psm1 (for configuration access)

<#
.SYNOPSIS
    System Optimization Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Analyzes system performance characteristics and identifies optimization opportunities.
    Audits startup programs, UI settings, registry health, disk usage, and network configuration.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: LoggingManager.psm1, WMI/CIM access
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
# v3.0 Type 1 module - imported by Type 2 modules
# Import CoreInfrastructure for configuration and logging
$ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}
else {
    # Fallback functions if CoreInfrastructure not available
    function Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
    function Get-SessionPath {
        param($Category, $SubCategory, $FileName)
        Write-Warning "CoreInfrastructure not available - using fallback path"
        return $FileName
    }
}

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive system performance audit

.DESCRIPTION
    Analyzes system performance characteristics and identifies optimization opportunities
    across startup programs, UI settings, registry, disk usage, and network configuration.

.PARAMETER IncludeStartup
    Audit startup programs and services

.PARAMETER IncludeUI
    Audit UI and visual effects settings

.PARAMETER IncludeRegistry
    Audit registry health and optimization opportunities

.PARAMETER IncludeDisk
    Audit disk usage and performance

.PARAMETER IncludeNetwork
    Audit network configuration and performance

.PARAMETER UseCache
    Use cached results if available

.EXAMPLE
    $audit = Get-SystemOptimizationAudit

.EXAMPLE
    $audit = Get-SystemOptimizationAudit -IncludeStartup -IncludeDisk
#>
function Get-SystemOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludeStartup,

        [Parameter()]
        [switch]$IncludeUI,

        [Parameter()]
        [switch]$IncludeRegistry,

        [Parameter()]
        [switch]$IncludeDisk,

        [Parameter()]
        [switch]$IncludeNetwork,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information "🔍 Starting system optimization audit..." -InformationAction Continue
    
    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SystemOptimizationAudit' -Component 'SYSTEM-OPT-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPT-AUDIT' -Message 'Starting system optimization audit' -Data @{
            IncludeStartup  = $IncludeStartup
            IncludeUI       = $IncludeUI
            IncludeRegistry = $IncludeRegistry
            IncludeDisk     = $IncludeDisk
            IncludeNetwork  = $IncludeNetwork
        }
    }
    catch {
        # LoggingManager not available, continue with standard output
        Write-Information "System optimization audit started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'system-optimization-audit.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le 15) {
                    Write-Information "Using cached system optimization audit data" -InformationAction Continue
                    return Get-Content $cacheFile | ConvertFrom-Json
                }
            }
        }

        # Initialize audit results
        $auditResults = @{
            AuditTimestamp            = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SystemInfo                = Get-BasicSystemInfo
            OptimizationOpportunities = @()
            PerformanceMetrics        = @{}
            Recommendations           = @()
        }

        # Default to include all categories if none specified
        if (-not $IncludeStartup -and -not $IncludeUI -and -not $IncludeRegistry -and -not $IncludeDisk -and -not $IncludeNetwork) {
            $IncludeStartup = $IncludeUI = $IncludeRegistry = $IncludeDisk = $IncludeNetwork = $true
        }

        # Audit different categories
        if ($IncludeStartup) {
            Write-Information "  📋 Auditing startup programs and services..." -InformationAction Continue
            $auditResults.StartupAudit = Get-StartupOptimizationAudit
            $auditResults.OptimizationOpportunities += $auditResults.StartupAudit.Opportunities
        }

        if ($IncludeUI) {
            Write-Information "  🎨 Auditing UI and visual effects..." -InformationAction Continue
            $auditResults.UIAudit = Get-UIOptimizationAudit
            $auditResults.OptimizationOpportunities += $auditResults.UIAudit.Opportunities
        }

        if ($IncludeRegistry) {
            Write-Information "  📝 Auditing registry health..." -InformationAction Continue
            $auditResults.RegistryAudit = Get-RegistryOptimizationAudit
            $auditResults.OptimizationOpportunities += $auditResults.RegistryAudit.Opportunities
        }

        if ($IncludeDisk) {
            Write-Information "  💾 Auditing disk usage and performance..." -InformationAction Continue
            $auditResults.DiskAudit = Get-DiskOptimizationAudit
            $auditResults.OptimizationOpportunities += $auditResults.DiskAudit.Opportunities
        }

        if ($IncludeNetwork) {
            Write-Information "  🌐 Auditing network configuration..." -InformationAction Continue
            $auditResults.NetworkAudit = Get-NetworkOptimizationAudit
            $auditResults.OptimizationOpportunities += $auditResults.NetworkAudit.Opportunities
        }

        # Generate optimization score and recommendations
        $auditResults.OptimizationScore = Get-OptimizationScore -AuditResults $auditResults
        $auditResults.Recommendations = New-OptimizationRecommendations -AuditResults $auditResults

        Write-Information "✓ System optimization audit completed. Score: $($auditResults.OptimizationScore.Overall)/100" -InformationAction Continue

        # Save results to session data
        try {
            $outputPath = Get-SessionPath -Category 'data' -FileName 'system-optimization-audit.json'
            $auditResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.OptimizationOpportunities.Count
        }
        catch {}

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "System optimization audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        try {
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-OPT-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {}
        
        throw
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Gets basic system information for the audit
#>
function Get-BasicSystemInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $computerInfo = Get-ComputerInfo -Property WindowsProductName, WindowsVersion, WindowsBuildLabEx, TotalPhysicalMemory
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        
        return [PSCustomObject]@{
            OS                = $computerInfo.WindowsProductName
            Version           = $computerInfo.WindowsVersion
            Build             = $computerInfo.WindowsBuildLabEx
            RAM               = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
            CPU               = $cpu.Name
            Cores             = $cpu.NumberOfCores
            LogicalProcessors = $cpu.NumberOfLogicalProcessors
        }
    }
    catch {
        Write-Warning "Failed to get system info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Audits startup programs and services optimization opportunities
#>
function Get-StartupOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $opportunities = @()

    try {
        # Audit startup programs
        $startupApps = Get-CimInstance Win32_StartupCommand | Where-Object { $null -ne $_.Command }
        $highImpactApps = @()
        
        foreach ($app in $startupApps) {
            if ($app.Name -match 'Adobe|Steam|Spotify|Skype|Teams' -and $app.Command -notmatch 'Critical|System') {
                $highImpactApps += $app
                $opportunities += [PSCustomObject]@{
                    Category         = 'Startup'
                    Type             = 'DisableStartupApp'
                    Description      = "Disable non-essential startup application: $($app.Name)"
                    Impact           = 'High'
                    EstimatedSavings = '2-5 seconds boot time'
                    Target           = $app.Name
                }
            }
        }

        # Audit services
        $services = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Running' }
        $nonEssentialServices = $services | Where-Object { 
            $_.Name -match 'Fax|TabletInputService|WSearch|Spooler|Themes' -and
            $_.Name -notmatch 'BITS|Winmgmt|RpcSs|EventLog|Dhcp'
        }

        foreach ($service in $nonEssentialServices) {
            $opportunities += [PSCustomObject]@{
                Category         = 'Services'
                Type             = 'OptimizeService'
                Description      = "Optimize service startup: $($service.Name)"
                Impact           = 'Medium'
                EstimatedSavings = '1-2 seconds boot time'
                Target           = $service.Name
            }
        }

    }
    catch {
        Write-Warning "Failed to audit startup programs: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        TotalStartupApps    = $startupApps.Count
        HighImpactApps      = $highImpactApps.Count
        OptimizableServices = $nonEssentialServices.Count
        Opportunities       = $opportunities
    }
}

<#
.SYNOPSIS
    Audits UI and visual effects optimization opportunities
#>
function Get-UIOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $opportunities = @()

    try {
        # Check visual effects settings
        $visualEffects = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -ErrorAction SilentlyContinue
        if ($visualEffects -and $visualEffects.VisualFXSetting -ne 2) {
            $opportunities += [PSCustomObject]@{
                Category         = 'UI'
                Type             = 'OptimizeVisualEffects'
                Description      = 'Optimize visual effects for performance'
                Impact           = 'Medium'
                EstimatedSavings = '10-20% UI responsiveness'
                Target           = 'VisualEffects'
            }
        }

        # Check animation settings
        $animationSettings = Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue
        if ($animationSettings) {
            $opportunities += [PSCustomObject]@{
                Category         = 'UI'
                Type             = 'OptimizeAnimations'
                Description      = 'Optimize window animations for performance'
                Impact           = 'Low'
                EstimatedSavings = '5-10% UI responsiveness'
                Target           = 'Animations'
            }
        }

        # Check taskbar settings
        $taskbarSettings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction SilentlyContinue
        if ($taskbarSettings -and $taskbarSettings.TaskbarAnimations -ne 0) {
            $opportunities += [PSCustomObject]@{
                Category         = 'UI'
                Type             = 'OptimizeTaskbar'
                Description      = 'Disable taskbar animations for better performance'
                Impact           = 'Low'
                EstimatedSavings = '2-5% UI responsiveness'
                Target           = 'TaskbarAnimations'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit UI settings: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        UIOptimizations = $opportunities.Count
        Opportunities   = $opportunities
    }
}

<#
.SYNOPSIS
    Audits registry health and optimization opportunities
#>
function Get-RegistryOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $opportunities = @()

    try {
        # Check for common registry issues
        $tempFiles = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\*' -ErrorAction SilentlyContinue
        if ($tempFiles.Count -gt 100) {
            $opportunities += [PSCustomObject]@{
                Category         = 'Registry'
                Type             = 'CleanUserAssist'
                Description      = 'Clean UserAssist registry entries'
                Impact           = 'Low'
                EstimatedSavings = '1-2% registry performance'
                Target           = 'UserAssist'
            }
        }

        # Check prefetch settings
        $prefetch = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -ErrorAction SilentlyContinue
        if ($prefetch -and $prefetch.EnablePrefetcher -eq 0) {
            $opportunities += [PSCustomObject]@{
                Category         = 'Registry'
                Type             = 'EnablePrefetch'
                Description      = 'Enable prefetch for better performance'
                Impact           = 'Medium'
                EstimatedSavings = '5-10% application startup time'
                Target           = 'Prefetch'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit registry: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        RegistryOptimizations = $opportunities.Count
        Opportunities         = $opportunities
    }
}

<#
.SYNOPSIS
    Audits disk usage and performance optimization opportunities
#>
function Get-DiskOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $opportunities = @()

    try {
        # Check disk space on system drive
        $systemDrive = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and $_.DeviceID -eq $env:SystemDrive }
        $freeSpacePercent = ($systemDrive.FreeSpace / $systemDrive.Size) * 100

        if ($freeSpacePercent -lt 20) {
            $opportunities += [PSCustomObject]@{
                Category         = 'Disk'
                Type             = 'DiskCleanup'
                Description      = "System drive has low free space ($([math]::Round($freeSpacePercent, 1))%)"
                Impact           = 'High'
                EstimatedSavings = '1-5GB disk space'
                Target           = 'SystemDrive'
            }
        }

        # Check temp folders
        $tempFolders = @($env:TEMP, "$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch")
        foreach ($folder in $tempFolders) {
            if (Test-Path $folder) {
                $tempSize = (Get-ChildItem $folder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($tempSize -gt 100MB) {
                    $opportunities += [PSCustomObject]@{
                        Category         = 'Disk'
                        Type             = 'CleanTempFiles'
                        Description      = "Clean temporary files in $folder ($([math]::Round($tempSize/1MB, 1)) MB)"
                        Impact           = 'Medium'
                        EstimatedSavings = "$([math]::Round($tempSize/1MB, 1)) MB disk space"
                        Target           = $folder
                    }
                }
            }
        }

        # Check for fragmentation (SSD vs HDD)
        $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        foreach ($drive in $drives) {
            $physical = Get-CimInstance Win32_DiskDrive | Where-Object { $_.DeviceID -like "*$($drive.DeviceID.Replace(':',''))*" }
            if ($physical -and $physical.MediaType -match 'Fixed hard disk' -and $physical.MediaType -notmatch 'SSD') {
                $opportunities += [PSCustomObject]@{
                    Category         = 'Disk'
                    Type             = 'DefragmentDisk'
                    Description      = "Defragment traditional hard disk ($($drive.DeviceID))"
                    Impact           = 'Medium'
                    EstimatedSavings = '10-30% disk performance'
                    Target           = $drive.DeviceID
                }
            }
        }

    }
    catch {
        Write-Warning "Failed to audit disk: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        DiskOptimizations = $opportunities.Count
        Opportunities     = $opportunities
    }
}

<#
.SYNOPSIS
    Audits network configuration optimization opportunities
#>
function Get-NetworkOptimizationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $opportunities = @()

    try {
        # Check network adapter settings
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $adapters) {
            # Check if RSS is enabled for high-speed adapters
            if ($adapter.LinkSpeed -gt 1000000000) {
                # > 1Gbps
                $rss = Get-NetAdapterRss -Name $adapter.Name -ErrorAction SilentlyContinue
                if ($rss -and -not $rss.Enabled) {
                    $opportunities += [PSCustomObject]@{
                        Category         = 'Network'
                        Type             = 'EnableRSS'
                        Description      = "Enable Receive Side Scaling (RSS) on $($adapter.Name)"
                        Impact           = 'Medium'
                        EstimatedSavings = '10-20% network performance'
                        Target           = $adapter.Name
                    }
                }
            }
        }

        # Check DNS settings
        $dnsServers = Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 }
        $publicDNS = @('8.8.8.8', '1.1.1.1', '208.67.222.222')
        $hasOptimalDNS = $false
        
        foreach ($dns in $dnsServers) {
            if ($dns.ServerAddresses | Where-Object { $_ -in $publicDNS }) {
                $hasOptimalDNS = $true
                break
            }
        }

        if (-not $hasOptimalDNS) {
            $opportunities += [PSCustomObject]@{
                Category         = 'Network'
                Type             = 'OptimizeDNS'
                Description      = 'Configure faster DNS servers (Google DNS, Cloudflare DNS)'
                Impact           = 'Medium'
                EstimatedSavings = '10-50% DNS lookup time'
                Target           = 'DNS'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit network: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        NetworkOptimizations = $opportunities.Count
        Opportunities        = $opportunities
    }
}

<#
.SYNOPSIS
    Calculates overall optimization score
#>
function Get-OptimizationScore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $baseScore = 100
    $deductions = 0

    # Deduct points based on optimization opportunities
    foreach ($opportunity in $AuditResults.OptimizationOpportunities) {
        switch ($opportunity.Impact) {
            'High' { $deductions += 15 }
            'Medium' { $deductions += 8 }
            'Low' { $deductions += 3 }
        }
    }

    $overallScore = [math]::Max(0, $baseScore - $deductions)

    return [PSCustomObject]@{
        Overall          = $overallScore
        MaxScore         = $baseScore
        Deductions       = $deductions
        OpportunityCount = $AuditResults.OptimizationOpportunities.Count
        Category         = if ($overallScore -ge 90) { 'Excellent' } 
        elseif ($overallScore -ge 75) { 'Good' } 
        elseif ($overallScore -ge 60) { 'Fair' } 
        else { 'Needs Improvement' }
    }
}

<#
.SYNOPSIS
    Generates optimization recommendations based on audit results
#>
function New-OptimizationRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $recommendations = @()

    # Group opportunities by impact and generate recommendations
    $highImpact = $AuditResults.OptimizationOpportunities | Where-Object { $_.Impact -eq 'High' }
    $mediumImpact = $AuditResults.OptimizationOpportunities | Where-Object { $_.Impact -eq 'Medium' }

    if ($highImpact.Count -gt 0) {
        $recommendations += "Priority 1: Address $($highImpact.Count) high-impact optimizations for immediate performance gains"
    }

    if ($mediumImpact.Count -gt 0) {
        $recommendations += "Priority 2: Implement $($mediumImpact.Count) medium-impact optimizations for steady improvements"
    }

    if ($AuditResults.OptimizationOpportunities.Count -eq 0) {
        $recommendations += "System is well-optimized. Consider periodic maintenance and monitoring."
    }

    return $recommendations
}

#endregion

# Export public functions
Export-ModuleMember -Function 'Get-SystemOptimizationAudit'