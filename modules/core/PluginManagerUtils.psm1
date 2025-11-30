# Additional utility functions for PluginManager.psm1
# This file extends the core plugin manager with additional functionality

#region Plugin Health and Monitoring

<#
.SYNOPSIS
    Start health monitoring for a loaded plugin.

.DESCRIPTION
    Initiates continuous health monitoring for a plugin including:
    - Memory usage tracking
    - Execution time monitoring
    - Error rate tracking
    - Performance degradation detection

.PARAMETER PluginId
    Plugin identifier to monitor
#>
function Start-PluginHealthMonitoring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId
    )
    
    try {
        if (-not $script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
            Write-Warning "⚠️ Cannot start monitoring for unloaded plugin: $PluginId"
            return
        }
        
        $loadedPlugin = $script:PluginContext.LoadedPlugins[$PluginId]
        
        # Initialize health metrics if not exists
        if (-not $script:PluginContext.PerformanceMetrics.ContainsKey($PluginId)) {
            $script:PluginContext.PerformanceMetrics[$PluginId] = @{
                HealthChecks   = @()
                ExecutionTimes = @()
                MemoryUsage    = @()
                ErrorCount     = 0
                LastError      = $null
                HealthScore    = 100
            }
        }
        
        # Perform initial health check
        $healthResult = Test-PluginHealth -PluginId $PluginId
        $loadedPlugin.HealthStatus = if ($healthResult.IsHealthy) { 'Healthy' } else { 'Unhealthy' }
        $loadedPlugin.LastHealthCheck = Get-Date
        
        Write-Verbose "✅ Health monitoring started for plugin: $($loadedPlugin.Plugin.Name)"
    }
    catch {
        Write-Warning "⚠️ Failed to start health monitoring for plugin $PluginId : $_"
    }
}

<#
.SYNOPSIS
    Perform health check on a plugin.

.DESCRIPTION
    Tests plugin health by calling its Test-PluginHealth method if available
    and checking system metrics.

.PARAMETER PluginId
    Plugin identifier to check

.OUTPUTS
    [PSCustomObject] Health check result
#>
function Test-PluginHealth {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId
    )
    
    try {
        if (-not $script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
            return [PSCustomObject]@{
                IsHealthy = $false
                Issues    = @("Plugin not loaded")
                CheckTime = Get-Date
            }
        }
        
        $loadedPlugin = $script:PluginContext.LoadedPlugins[$PluginId]
        $issues = @()
        
        # Check if plugin module is still loaded
        $moduleLoaded = Get-Module -Name $loadedPlugin.ModuleInfo.Name -ErrorAction SilentlyContinue
        if (-not $moduleLoaded) {
            $issues += "Plugin module no longer loaded"
        }
        
        # Try to call plugin's health check method if available
        try {
            $healthFunction = Get-Command "Test-PluginHealth" -Module $loadedPlugin.ModuleInfo.Name -ErrorAction SilentlyContinue
            if ($healthFunction) {
                $pluginHealthResult = & $healthFunction
                if ($pluginHealthResult -eq $false) {
                    $issues += "Plugin self-health check failed"
                }
            }
        }
        catch {
            $issues += "Plugin health check method failed: $_"
        }
        
        # Check error rate
        $metrics = $script:PluginContext.PerformanceMetrics[$PluginId]
        if ($metrics.ErrorCount -gt $script:PluginConfig.lifecycle.maxErrorCount) {
            $issues += "Plugin error count exceeded threshold: $($metrics.ErrorCount)"
        }
        
        $isHealthy = $issues.Count -eq 0
        
        # Update health metrics
        $healthCheck = @{
            Timestamp = Get-Date
            IsHealthy = $isHealthy
            Issues    = $issues
        }
        
        $metrics.HealthChecks += $healthCheck
        
        # Keep only recent health checks
        if ($metrics.HealthChecks.Count -gt 10) {
            $metrics.HealthChecks = $metrics.HealthChecks | Select-Object -Last 10
        }
        
        # Calculate health score
        $recentHealthy = ($metrics.HealthChecks | Where-Object { $_.IsHealthy }).Count
        $metrics.HealthScore = [math]::Round(($recentHealthy / $metrics.HealthChecks.Count) * 100, 2)
        
        return [PSCustomObject]@{
            IsHealthy   = $isHealthy
            Issues      = $issues
            HealthScore = $metrics.HealthScore
            CheckTime   = Get-Date
        }
    }
    catch {
        return [PSCustomObject]@{
            IsHealthy   = $false
            Issues      = @("Health check failed: $_")
            HealthScore = 0
            CheckTime   = Get-Date
        }
    }
}

<#
.SYNOPSIS
    Get comprehensive status of all plugins.

.DESCRIPTION
    Returns detailed status information for all registered and loaded plugins.

.OUTPUTS
    [PSCustomObject] Plugin status summary
#>
function Get-PluginStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $registeredCount = $script:PluginRegistry.Count
        $loadedCount = $script:PluginContext.LoadedPlugins.Count
        $healthyCount = 0
        $unhealthyCount = 0
        
        $pluginStatuses = @()
        
        foreach ($pluginId in $script:PluginRegistry.Keys) {
            $plugin = $script:PluginRegistry[$pluginId]
            $isLoaded = $script:PluginContext.LoadedPlugins.ContainsKey($pluginId)
            $healthStatus = 'Unknown'
            $healthScore = 0
            
            if ($isLoaded) {
                $loadedPlugin = $script:PluginContext.LoadedPlugins[$pluginId]
                $healthStatus = $loadedPlugin.HealthStatus
                
                if ($script:PluginContext.PerformanceMetrics.ContainsKey($pluginId)) {
                    $healthScore = $script:PluginContext.PerformanceMetrics[$pluginId].HealthScore
                }
                
                if ($healthStatus -eq 'Healthy') {
                    $healthyCount++
                }
                else {
                    $unhealthyCount++
                }
            }
            
            $pluginStatuses += [PSCustomObject]@{
                Id             = $pluginId
                Name           = $plugin.Name
                Version        = $plugin.Version
                Interface      = $plugin.Interface
                Category       = $plugin.Category
                Status         = $plugin.Status
                IsLoaded       = $isLoaded
                HealthStatus   = $healthStatus
                HealthScore    = $healthScore
                LoadTime       = $plugin.LoadTime
                ExecutionCount = if ($isLoaded) { $script:PluginContext.LoadedPlugins[$pluginId].ExecutionCount } else { 0 }
                LastError      = $plugin.LastError
            }
        }
        
        return [PSCustomObject]@{
            Summary   = @{
                RegisteredPlugins = $registeredCount
                LoadedPlugins     = $loadedCount
                HealthyPlugins    = $healthyCount
                UnhealthyPlugins  = $unhealthyCount
                SystemStartTime   = $script:PluginContext.StartTime
            }
            Plugins   = $pluginStatuses
            Timestamp = Get-Date
        }
    }
    catch {
        Write-Error "❌ Failed to get plugin status: $_"
        return $null
    }
}

#endregion

#region Plugin Configuration Management

<#
.SYNOPSIS
    Get default plugin system configuration.

.DESCRIPTION
    Returns default configuration for plugin system when config file is not available.

.OUTPUTS
    [hashtable] Default plugin configuration
#>
function Get-DefaultPluginConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return @{
        pluginPaths          = @{
            systemPlugins     = "plugins\system"
            userPlugins       = "plugins\user"  
            thirdPartyPlugins = "plugins\third-party"
            pluginCache       = "temp_files\plugin-cache"
            pluginLogs        = "temp_files\plugin-logs"
            pluginData        = "temp_files\plugin-data"
        }
        pluginSystem         = @{
            autoDiscovery     = $true
            autoLoadOnStartup = $true
            enableLogging     = $true
            logLevel          = "Information"
        }
        security             = @{
            enableCodeAnalysis  = $true
            sandboxingEnabled   = $false
            allowedPublishers   = @()
            quarantineUntrusted = $true
            maxPluginSize       = 10MB
        }
        validation           = @{
            enableMetadataValidation = $true
            requireDigitalSignatures = $false
            maxPluginSize            = 10485760  # 10MB
            allowedInterfaces        = @("IMaintenancePlugin", "IInventoryPlugin", "IReportPlugin", "ISystemPlugin", "ISecurityPlugin")
        }
        lifecycle            = @{
            enableHealthMonitoring = $true
            healthCheckInterval    = 300  # 5 minutes
            maxErrorCount          = 5
            autoUnloadUnhealthy    = $false
        }
        dependencyManagement = @{
            autoInstallDependencies   = $false
            allowCircularDependencies = $false
            dependencyTimeout         = 30
        }
        sandboxing           = @{
            blockedCmdlets         = @(
                "Invoke-Expression", "Invoke-Command", "Start-Process",
                "Remove-Computer", "Restart-Computer", "Stop-Computer",
                "Format-Volume", "Clear-Disk", "Remove-Partition"
            )
            allowedPaths           = @("temp_files\", "plugins\", "logs\")
            restrictNetworkAccess  = $true
            restrictRegistryAccess = $true
        }
    }
}

<#
.SYNOPSIS
    Update plugin configuration for a specific plugin.

.DESCRIPTION
    Updates the configuration settings for a loaded plugin.

.PARAMETER PluginId
    Plugin identifier

.PARAMETER Configuration
    Configuration hashtable to apply

.OUTPUTS
    [bool] True if configuration updated successfully
#>
function Set-PluginConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )
    
    try {
        if (-not $script:PluginRegistry.ContainsKey($PluginId)) {
            Write-Error "Plugin not found: $PluginId"
            return $false
        }
        
        $plugin = $script:PluginRegistry[$PluginId]
        
        # Update plugin configuration
        $plugin.Configuration = $Configuration
        
        # If plugin is loaded and has a configuration method, call it
        if ($script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
            $loadedPlugin = $script:PluginContext.LoadedPlugins[$PluginId]
            
            try {
                $setConfigFunction = Get-Command "Set-PluginConfiguration" -Module $loadedPlugin.ModuleInfo.Name -ErrorAction SilentlyContinue
                if ($setConfigFunction) {
                    $result = & $setConfigFunction -Configuration $Configuration
                    if ($result -eq $false) {
                        Write-Warning "⚠️ Plugin rejected configuration update: $($plugin.Name)"
                        return $false
                    }
                }
            }
            catch {
                Write-Warning "⚠️ Failed to apply configuration to plugin: $_"
                return $false
            }
        }
        
        Write-Verbose "✅ Plugin configuration updated: $($plugin.Name)"
        return $true
    }
    catch {
        Write-Error "❌ Failed to update plugin configuration: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Get configuration for a specific plugin.

.PARAMETER PluginId
    Plugin identifier

.OUTPUTS
    [hashtable] Plugin configuration or $null if not found
#>
function Get-PluginConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId
    )
    
    try {
        if (-not $script:PluginRegistry.ContainsKey($PluginId)) {
            Write-Error "Plugin not found: $PluginId"
            return $null
        }
        
        return $script:PluginRegistry[$PluginId].Configuration
    }
    catch {
        Write-Error "❌ Failed to get plugin configuration: $_"
        return $null
    }
}

#endregion

#region Plugin Execution and Invocation

<#
.SYNOPSIS
    Invoke a method on a loaded plugin with performance tracking.

.DESCRIPTION
    Executes a plugin method with comprehensive monitoring:
    - Performance metrics tracking
    - Error handling and logging
    - Execution count tracking
    - Health status updates

.PARAMETER PluginId
    Plugin identifier

.PARAMETER MethodName
    Method name to invoke

.PARAMETER Parameters
    Parameters to pass to the method

.OUTPUTS
    Plugin method return value or $null on error
#>
function Invoke-PluginMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId,
        
        [Parameter(Mandatory = $true)]
        [string]$MethodName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )
    
    try {
        if (-not $script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
            Write-Error "Plugin not loaded: $PluginId"
            return $null
        }
        
        $loadedPlugin = $script:PluginContext.LoadedPlugins[$PluginId]
        $plugin = $loadedPlugin.Plugin
        
        Write-Verbose "🔄 Invoking plugin method: $($plugin.Name).$MethodName"
        
        # Check if method exists
        $method = Get-Command $MethodName -Module $loadedPlugin.ModuleInfo.Name -ErrorAction SilentlyContinue
        if (-not $method) {
            Write-Error "Method not found in plugin: $MethodName"
            return $null
        }
        
        # Track execution start
        $executionStart = Get-Date
        
        try {
            # Invoke the method with parameters
            if ($Parameters.Count -gt 0) {
                $result = & $method @Parameters
            }
            else {
                $result = & $method
            }
            
            # Track successful execution
            $executionTime = (Get-Date) - $executionStart
            $loadedPlugin.ExecutionCount++
            $loadedPlugin.TotalExecutionTime += $executionTime
            
            # Update performance metrics
            if ($script:PluginContext.PerformanceMetrics.ContainsKey($PluginId)) {
                $metrics = $script:PluginContext.PerformanceMetrics[$PluginId]
                $metrics.ExecutionTimes += @{
                    Method    = $MethodName
                    Duration  = $executionTime
                    Timestamp = Get-Date
                }
                
                # Keep only recent execution times
                if ($metrics.ExecutionTimes.Count -gt 50) {
                    $metrics.ExecutionTimes = $metrics.ExecutionTimes | Select-Object -Last 50
                }
            }
            
            Write-Verbose "✅ Plugin method executed successfully: $($plugin.Name).$MethodName (${executionTime}ms)"
            return $result
        }
        catch {
            # Track execution error
            $loadedPlugin.LastError = $_.Exception.Message
            $plugin.LastError = $_.Exception.Message
            
            # Update error metrics
            if ($script:PluginContext.PerformanceMetrics.ContainsKey($PluginId)) {
                $metrics = $script:PluginContext.PerformanceMetrics[$PluginId]
                $metrics.ErrorCount++
                $metrics.LastError = @{
                    Method    = $MethodName
                    Error     = $_.Exception.Message
                    Timestamp = Get-Date
                }
            }
            
            Write-Error "❌ Plugin method execution failed: $($plugin.Name).$MethodName - $_"
            throw
        }
    }
    catch {
        Write-Error "❌ Failed to invoke plugin method: $_"
        return $null
    }
}

#endregion

# Export additional utility functions
Export-ModuleMember -Function @(
    'Start-PluginHealthMonitoring',
    'Test-PluginHealth',
    'Get-PluginStatus',
    'Get-DefaultPluginConfiguration',
    'Set-PluginConfiguration',
    'Get-PluginConfiguration',
    'Invoke-PluginMethod'
)