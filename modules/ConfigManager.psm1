# ConfigManager Module
# Handles loading and validation of configuration files

function Import-MaintenanceConfig {
    <#
    .SYNOPSIS
    Loads and validates the maintenance configuration file.
    
    .PARAMETER ConfigPath
    Path to the configuration JSON file.
    
    .OUTPUTS
    Returns validated configuration object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }
        
        $configContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $config = $configContent | ConvertFrom-Json -ErrorAction Stop
        
        # Validate required sections
        $requiredSections = @('system', 'dependencies', 'maintenanceTasks')
        foreach ($section in $requiredSections) {
            if (-not $config.PSObject.Properties[$section]) {
                throw "Missing required configuration section: $section"
            }
        }
        
        Write-Verbose "Configuration loaded successfully from: $ConfigPath"
        return $config
    }
    catch {
        Write-Error "Failed to load configuration: $($_.Exception.Message)"
        throw
    }
}

function Get-EnabledTasks {
    <#
    .SYNOPSIS
    Returns list of enabled maintenance tasks sorted by priority.
    
    .PARAMETER Config
    Configuration object containing task definitions.
    
    .OUTPUTS
    Returns array of enabled task objects sorted by priority.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    $enabledTasks = @()
    
    foreach ($taskProperty in $Config.maintenanceTasks.PSObject.Properties) {
        $task = $taskProperty.Value
        if ($task.enabled -eq $true) {
            $taskObject = [PSCustomObject]@{
                Name = $taskProperty.Name
                Description = $task.description
                Priority = $task.priority
                Settings = $task
            }
            $enabledTasks += $taskObject
        }
    }
    
    return $enabledTasks | Sort-Object Priority
}

function Test-SystemRequirements {
    <#
    .SYNOPSIS
    Validates system meets minimum requirements from configuration.
    
    .PARAMETER Config
    Configuration object containing system requirements.
    
    .OUTPUTS
    Returns true if requirements are met, false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    try {
        # Check Windows version
        $osVersion = [System.Environment]::OSVersion.Version
        $minVersion = [Version]$Config.system.minWindowsVersion
        
        if ($osVersion -lt $minVersion) {
            Write-Error "Minimum Windows version required: $($Config.system.minWindowsVersion). Current: $osVersion"
            return $false
        }
        
        # Check admin privileges
        if ($Config.system.requiresAdmin) {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
            if (-not $isAdmin) {
                Write-Error "Administrator privileges required but not present."
                return $false
            }
        }
        
        Write-Verbose "System requirements validation passed."
        return $true
    }
    catch {
        Write-Error "Failed to validate system requirements: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Import-MaintenanceConfig, Get-EnabledTasks, Test-SystemRequirements
