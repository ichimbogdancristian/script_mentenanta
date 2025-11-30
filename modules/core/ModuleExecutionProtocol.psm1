#Requires -Version 7.0

<#
.SYNOPSIS
    Module Execution Protocol - Core orchestration infrastructure

.DESCRIPTION
    Provides standardized module execution protocol, dependency management,
    completion reporting, and comprehensive error handling for the maintenance automation system.

.NOTES
    Module Type: Core Infrastructure  
    Author: Windows Maintenance Automation Project
    Version: 2.1.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Management.Automation

#region Module Execution Classes

class ModuleManifest {
    [string] $Name
    [string] $Version
    [string] $Description
    [string] $Type  # Type1, Type2, Core
    [string] $Category
    [string] $ModulePath
    [string] $EntryFunction
    [string[]] $Dependencies = @()
    [bool] $RequiresElevation = $false
    [int] $TimeoutSeconds = 300  # 5 minutes default
    [hashtable] $Parameters = @{}
    [string[]] $ConfigurationDependencies = @()
    [hashtable] $Metadata = @{}
    
    ModuleManifest([hashtable] $Properties) {
        foreach ($key in $Properties.Keys) {
            if ($this.PSObject.Properties.Name -contains $key) {
                $this.$key = $Properties[$key]
            }
        }
    }
}

class ModuleExecutionContext {
    [string] $ModuleName
    [string] $ModulePath
    [string] $ExecutionId
    [datetime] $StartTime
    [hashtable] $Parameters = @{}
    [string[]] $Dependencies = @()
    [bool] $RequiresElevation = $false
    [int] $TimeoutSeconds = 300
    [System.Threading.CancellationTokenSource] $CancellationTokenSource
    [hashtable] $SharedData = @{}
    [hashtable] $Configuration = @{}
    [bool] $DryRun = $false
    
    # Default constructor
    ModuleExecutionContext() {
        $this.ExecutionId = [System.Guid]::NewGuid().ToString()
        $this.StartTime = Get-Date
        $this.Dependencies = @()
        $this.RequiresElevation = $false
        $this.TimeoutSeconds = 300
        $this.CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
        $this.Configuration = @{}
        $this.DryRun = $false
        $this.Parameters = @{}
    }
    
    ModuleExecutionContext([ModuleManifest] $Manifest, [hashtable] $GlobalConfig, [bool] $IsDryRun) {
        $this.ModuleName = $Manifest.Name
        $this.ModulePath = $Manifest.ModulePath
        $this.ExecutionId = [System.Guid]::NewGuid().ToString()
        $this.StartTime = Get-Date
        $this.Dependencies = $Manifest.Dependencies
        $this.RequiresElevation = $Manifest.RequiresElevation
        $this.TimeoutSeconds = $Manifest.TimeoutSeconds
        $this.CancellationTokenSource = New-Object System.Threading.CancellationTokenSource
        $this.Configuration = $GlobalConfig
        $this.DryRun = $IsDryRun
        $this.Parameters = $Manifest.Parameters.Clone()
    }
}

class ModuleExecutionResult {
    [string] $ModuleName
    [string] $ExecutionId
    [bool] $Success = $false
    [object] $Output = $null
    [string] $Error = $null
    [datetime] $StartTime
    [datetime] $EndTime
    [double] $DurationSeconds = 0
    [hashtable] $Metrics = @{}
    [string[]] $DependenciesUsed = @()
    [bool] $RequiredPrivileges = $false
    [string] $CompletionStatus = 'Unknown'  # Success, Failed, Timeout, Cancelled, DependencyFailure
    [hashtable] $DiagnosticData = @{}
    [System.Collections.Generic.List[string]] $Warnings = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $ConfigurationErrors = [System.Collections.Generic.List[string]]::new()
    
    ModuleExecutionResult([ModuleExecutionContext] $Context) {
        $this.ModuleName = $Context.ModuleName
        $this.ExecutionId = $Context.ExecutionId
        $this.StartTime = $Context.StartTime
        $this.DependenciesUsed = $Context.Dependencies
        $this.RequiredPrivileges = $Context.RequiresElevation
    }
    
    [void] Complete([bool] $IsSuccess, [object] $ResultOutput, [string] $ErrorMessage) {
        $this.EndTime = Get-Date
        $this.DurationSeconds = ($this.EndTime - $this.StartTime).TotalSeconds
        $this.Success = $IsSuccess
        $this.Output = $ResultOutput
        $this.Error = $ErrorMessage
        $this.CompletionStatus = if ($IsSuccess) { 'Success' } else { 'Failed' }
    }
    
    [void] Timeout() {
        $this.EndTime = Get-Date
        $this.DurationSeconds = ($this.EndTime - $this.StartTime).TotalSeconds
        $this.Success = $false
        $this.Error = "Module execution timed out after $($this.DurationSeconds) seconds"
        $this.CompletionStatus = 'Timeout'
    }
    
    [void] Cancel() {
        $this.EndTime = Get-Date
        $this.DurationSeconds = ($this.EndTime - $this.StartTime).TotalSeconds
        $this.Success = $false
        $this.Error = "Module execution was cancelled"
        $this.CompletionStatus = 'Cancelled'
    }
    
    [void] DependencyFailure([string[]] $FailedDependencies) {
        $this.EndTime = Get-Date
        $this.DurationSeconds = 0
        $this.Success = $false
        $this.Error = "Module skipped due to failed dependencies: $($FailedDependencies -join ', ')"
        $this.CompletionStatus = 'DependencyFailure'
    }
}

#endregion

#region Dependency Management

class DependencyResolver {
    [ModuleManifest[]] $Modules = @()
    [hashtable] $ModuleIndex = @{}
    [List[string]] $ExecutionOrder = [List[string]]::new()
    [hashtable] $DependencyGraph = @{}
    
    [void] AddModule([ModuleManifest] $Module) {
        $this.Modules += $Module
        $this.ModuleIndex[$Module.Name] = $Module
        $this.DependencyGraph[$Module.Name] = $Module.Dependencies
    }
    
    [List[string]] ResolveDependencyOrder() {
        $visited = @{}
        $visiting = @{}
        $order = [List[string]]::new()
        
        foreach ($moduleName in $this.ModuleIndex.Keys) {
            if (-not $visited.ContainsKey($moduleName)) {
                $this.TopologicalSort($moduleName, $visited, $visiting, $order)
            }
        }
        
        $this.ExecutionOrder = $order
        return $order
    }
    
    [void] TopologicalSort([string] $ModuleName, [hashtable] $Visited, [hashtable] $Visiting, [List[string]] $Order) {
        if ($Visiting.ContainsKey($ModuleName)) {
            throw "Circular dependency detected involving module: $ModuleName"
        }
        
        if ($Visited.ContainsKey($ModuleName)) {
            return
        }
        
        $Visiting[$ModuleName] = $true
        
        if ($this.DependencyGraph.ContainsKey($ModuleName)) {
            foreach ($dependency in $this.DependencyGraph[$ModuleName]) {
                if ($this.ModuleIndex.ContainsKey($dependency)) {
                    $this.TopologicalSort($dependency, $Visited, $Visiting, $Order)
                } else {
                    Write-Warning "Module '$ModuleName' has unknown dependency: $dependency"
                }
            }
        }
        
        $Visiting.Remove($ModuleName)
        $Visited[$ModuleName] = $true
        $Order.Add($ModuleName)
    }
    
    [string[]] GetFailedDependencies([string] $ModuleName, [hashtable] $CompletedModules) {
        $failedDeps = @()
        
        if (-not $this.ModuleIndex.ContainsKey($ModuleName)) {
            return $failedDeps
        }
        
        $module = $this.ModuleIndex[$ModuleName]
        
        foreach ($dependency in $module.Dependencies) {
            if ($CompletedModules.ContainsKey($dependency)) {
                $depResult = $CompletedModules[$dependency]
                if (-not $depResult.Success) {
                    $failedDeps += $dependency
                }
            } else {
                $failedDeps += $dependency
            }
        }
        
        return $failedDeps
    }
}

#endregion

#region Module Execution Engine

class ModuleExecutor {
    [DependencyResolver] $DependencyResolver
    [hashtable] $GlobalConfiguration = @{}
    [bool] $DryRun = $false
    [hashtable] $SharedModuleData = @{}
    [ConcurrentDictionary[string, ModuleExecutionResult]] $ExecutionResults
    [System.Collections.Concurrent.ConcurrentQueue[string]] $LogQueue
    
    ModuleExecutor([hashtable] $Config, [bool] $IsDryRun) {
        $this.DependencyResolver = [DependencyResolver]::new()
        $this.GlobalConfiguration = $Config
        $this.DryRun = $IsDryRun
        $this.ExecutionResults = [ConcurrentDictionary[string, ModuleExecutionResult]]::new()
        $this.LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    }
    
    [void] RegisterModule([ModuleManifest] $Module) {
        Write-Log "Registering module: $($Module.Name)" -Level INFO -Component MODULE_EXECUTOR
        $this.DependencyResolver.AddModule($Module)
    }
    
    [ModuleExecutionResult[]] ExecuteAllModules([string[]] $SelectedModules = @()) {
        Write-Log "Starting module execution engine" -Level INFO -Component MODULE_EXECUTOR
        
        # Resolve execution order
        try {
            $executionOrder = $this.DependencyResolver.ResolveDependencyOrder()
            Write-Log "Dependency resolution completed. Execution order: $($executionOrder -join ' → ')" -Level SUCCESS -Component MODULE_EXECUTOR
        } catch {
            Write-Log "Dependency resolution failed: $_" -Level ERROR -Component MODULE_EXECUTOR
            throw "Failed to resolve module dependencies: $_"
        }
        
        # Filter by selected modules if specified
        if ($SelectedModules.Count -gt 0) {
            $executionOrder = $executionOrder | Where-Object { $_ -in $SelectedModules }
            Write-Log "Filtered execution to selected modules: $($executionOrder -join ', ')" -Level INFO -Component MODULE_EXECUTOR
        }
        
        $results = @()
        $completedModules = @{}
        
        foreach ($moduleName in $executionOrder) {
            try {
                $manifest = $this.DependencyResolver.ModuleIndex[$moduleName]
                
                # Check for failed dependencies
                $failedDeps = $this.DependencyResolver.GetFailedDependencies($moduleName, $completedModules)
                
                if ($failedDeps.Count -gt 0) {
                    Write-Log "Module '$moduleName' skipped due to failed dependencies: $($failedDeps -join ', ')" -Level WARN -Component MODULE_EXECUTOR
                    $result = [ModuleExecutionResult]::new([ModuleExecutionContext]::new($manifest, $this.GlobalConfiguration, $this.DryRun))
                    $result.DependencyFailure($failedDeps)
                    $this.ExecutionResults[$moduleName] = $result
                    $completedModules[$moduleName] = $result
                    $results += $result
                    continue
                }
                
                # Execute module
                Write-Log "Executing module: $moduleName" -Level INFO -Component MODULE_EXECUTOR
                Write-Log "Starting execution of $moduleName" -Level INFO -Component $moduleName
                $result = $this.ExecuteModule($manifest)
                
                $this.ExecutionResults[$moduleName] = $result
                $completedModules[$moduleName] = $result
                $results += $result
                
                # Log completion
                $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
                Write-Log "Module '$moduleName' completed with status: $status (Duration: $([math]::Round($result.DurationSeconds, 2))s)" -Level $(if ($result.Success) { "SUCCESS" } else { "ERROR" }) -Component MODULE_EXECUTOR
                Write-Log "Execution completed with status: $status (Duration: $([math]::Round($result.DurationSeconds, 2))s)" -Level $(if ($result.Success) { "SUCCESS" } else { "ERROR" }) -Component $moduleName
                
            } catch {
                Write-Log "Critical error executing module '$moduleName': $_" -Level ERROR -Component MODULE_EXECUTOR
                # Create error result with minimal context
                $context = [ModuleExecutionContext]::new()
                $context.ModuleName = $moduleName
                $context.StartTime = Get-Date
                $context.Configuration = $this.GlobalConfiguration
                $context.DryRun = $this.DryRun
                
                $errorResult = [ModuleExecutionResult]::new($context)
                $errorResult.Complete($false, $null, "Critical execution error: $_")
                $this.ExecutionResults[$moduleName] = $errorResult
                $completedModules[$moduleName] = $errorResult
                $results += $errorResult
            }
        }
        
        Write-Log "Module execution engine completed. Total modules: $($results.Count), Successful: $(($results | Where-Object Success).Count), Failed: $(($results | Where-Object { -not $_.Success }).Count)" -Level INFO -Component MODULE_EXECUTOR
        
        return $results
    }
    
    [ModuleExecutionResult] ExecuteModule([ModuleManifest] $Manifest) {
        $context = [ModuleExecutionContext]::new($Manifest, $this.GlobalConfiguration, $this.DryRun)
        $result = [ModuleExecutionResult]::new($context)
        
        try {
            # Prepare per-module log path - create logs in temp_files structure
            try {
                # Always use temp_files/logs structure for consistency
                if ($Global:MaintenanceLogFile) {
                    $mainLogDir = Split-Path $Global:MaintenanceLogFile -Parent
                    $moduleLogsDir = Join-Path $mainLogDir "temp_files\logs"
                } else {
                    # Fallback: use standardized path discovery for logs
                    try {
                        Import-Module (Join-Path (Split-Path $context.ModulePath -Parent) 'ConfigManager.psm1') -Force -ErrorAction Stop
                        $moduleEnv = Get-ModuleEnvironment -ModuleType 'Core'
                        $moduleLogsDir = $moduleEnv.LogsPath
                    } catch {
                        $moduleLogsDir = Join-Path (Split-Path $context.ModulePath -Parent) '..\..\temp_files\logs'
                    }
                }
                
                # Ensure the logs directory exists
                if (-not (Test-Path $moduleLogsDir)) {
                    New-Item -Path $moduleLogsDir -ItemType Directory -Force | Out-Null
                }
                $Global:ModuleLogFile = Join-Path $moduleLogsDir "$($Manifest.Name).log"
                
                # Initialize module log file with header
                $moduleLogHeader = @"
======================================================================
Module: $($Manifest.Name)
Type: $($Manifest.Type)
Description: $($Manifest.Description)
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
======================================================================

"@
                $moduleLogHeader | Out-File -FilePath $Global:ModuleLogFile -Encoding UTF8
                
            } catch {
                Write-Log "Failed to setup module log file: $($_.Exception.Message)" -Level WARN -Component MODULE_EXECUTOR
                Remove-Variable -Name ModuleLogFile -Scope Global -ErrorAction SilentlyContinue
            }

            # Validate privileges if required (with graceful degradation support)
            if ($context.RequiresElevation) {
                $isAdmin = $this.ValidateAdminPrivileges()
                if (-not $isAdmin -and -not $context.DryRun) {
                    # Check if we're in "seamless execution" mode (ForceAllModules without elevation)
                    if ($this.GlobalConfiguration.ContainsKey('ForceAllModules') -and $this.GlobalConfiguration['ForceAllModules']) {
                        Write-Log "Module '$($Manifest.Name)' requires elevation but running in ForceAllModules mode - attempting graceful execution" -Level WARN -Component MODULE_EXECUTOR
                        $result.Warnings.Add("Module executed without required administrator privileges - some operations may be skipped")
                    } else {
                        throw "Module requires Administrator privileges but current session is not elevated"
                    }
                }
            }
            
            # Load and validate module
            if (-not (Test-Path $context.ModulePath)) {
                throw "Module file not found: $($context.ModulePath)"
            }
            
            Write-Log "Loading module: $($context.ModulePath)" -Level INFO -Component MODULE_EXECUTOR
            Write-Log "Loading module from path: $($context.ModulePath)" -Level INFO -Component $Manifest.Name
            Import-Module $context.ModulePath -Force -ErrorAction Stop
            
            # Validate entry function exists
            if (-not (Get-Command $Manifest.EntryFunction -ErrorAction SilentlyContinue)) {
                throw "Entry function '$($Manifest.EntryFunction)' not found in module"
            }
            
            # Execute with timeout
            $executionTask = $this.ExecuteModuleWithTimeout($context, $Manifest)
            
            if ($executionTask.IsCompleted) {
                $moduleResult = $executionTask.Result
                $result.Complete($true, $moduleResult, $null)
            } else {
                $result.Timeout()
            }
            
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Module execution failed: $errorMessage" -Level ERROR -Component MODULE_EXECUTOR
            Write-Log "Execution failed with error: $errorMessage" -Level ERROR -Component $Manifest.Name
            $result.Complete($false, $null, $errorMessage)
            
            # Add specific error categorization
            if ($errorMessage -like "*privileges*" -or $errorMessage -like "*administrator*") {
                $result.ConfigurationErrors += "Privilege validation failed"
            } elseif ($errorMessage -like "*not found*") {
                $result.ConfigurationErrors += "Module or function not found"
            } elseif ($errorMessage -like "*timeout*") {
                $result.ConfigurationErrors += "Execution timeout"
            }
        }
        finally {
            # Ensure we clear the per-module log path to avoid cross-module leakage
            try { Remove-Variable -Name ModuleLogFile -Scope Global -ErrorAction SilentlyContinue } catch { }
        }

        return $result
    }
    
    [System.Threading.Tasks.Task] ExecuteModuleWithTimeout([ModuleExecutionContext] $Context, [ModuleManifest] $Manifest) {
        # Execute directly without threading for now to avoid Runspace issues
        try {
            # Prepare function parameters
            $funcParams = @{}
            
            # Add DryRun if supported
            if ((Get-Command $Manifest.EntryFunction).Parameters.ContainsKey('DryRun')) {
                $funcParams['DryRun'] = $Context.DryRun
            }
            
            # Add any custom parameters
            if ($Context.Parameters) {
                foreach ($key in $Context.Parameters.Keys) {
                    if ((Get-Command $Manifest.EntryFunction).Parameters.ContainsKey($key)) {
                        $funcParams[$key] = $Context.Parameters[$key]
                    }
                }
            }
            
            # Execute the function directly
            $functionResult = & $Manifest.EntryFunction @funcParams
            
            $result = @{
                Success = $true
                Output = $functionResult
                Error = $null
            }
            
            # Return as a completed task
            return [System.Threading.Tasks.Task]::FromResult([object]$result)
            
        } catch {
            $result = @{
                Success = $false
                Output = $null
                Error = $_.Exception.Message
            }
            
            # Return as a completed task with error
            return [System.Threading.Tasks.Task]::FromResult([object]$result)
        }
    }
    
    [bool] ValidateAdminPrivileges() {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch {
            Write-Log "Failed to validate admin privileges: $_" -Level WARN -Component MODULE_EXECUTOR
            return $false
        }
    }
}

#endregion

#region Logging Infrastructure

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        
        [Parameter()]
        [string]$Component = 'MODULE_PROTOCOL'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Write to console with colors
    $color = switch ($Level) {
        'DEBUG' { 'Gray' }
        'INFO' { 'White' }
        'SUCCESS' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # Write to log file if available
        if ($Global:MaintenanceLogFile -and (Test-Path (Split-Path $Global:MaintenanceLogFile))) {
            $logEntry | Add-Content -Path $Global:MaintenanceLogFile -ErrorAction SilentlyContinue
        }

        # Additionally write to a per-module log file if the orchestrator set one for the current module
        if ($Global:ModuleLogFile) {
            try {
                $moduleLogDir = Split-Path $Global:ModuleLogFile -Parent
                if (-not (Test-Path $moduleLogDir)) { New-Item -Path $moduleLogDir -ItemType Directory -Force | Out-Null }
                $logEntry | Add-Content -Path $Global:ModuleLogFile -ErrorAction SilentlyContinue
            } catch {
                # Non-fatal: continue writing other logs
                Write-Host "[WARN] Failed to write to module log $Global:ModuleLogFile: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
}

#endregion

#region Public Functions

function New-ModuleManifest {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Properties
    )
    
    return [ModuleManifest]::new($Properties)
}

function New-ModuleExecutor {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration,
        
        [Parameter()]
        [bool]$DryRun = $false
    )
    
    return [ModuleExecutor]::new($Configuration, $DryRun)
}

function New-ModuleExecutionResult {
    <#
    .SYNOPSIS
        Create a new ModuleExecutionResult object
    
    .PARAMETER ModuleName
        Name of the module
    
    .PARAMETER ExecutionId
        Optional execution identifier
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$ExecutionId = [guid]::NewGuid().ToString()
    )
    
    # Create a minimal context for the result
    $context = [ModuleExecutionContext]::new()
    $context.ModuleName = $ModuleName
    $context.ExecutionId = $ExecutionId
    $context.StartTime = Get-Date
    
    return [ModuleExecutionResult]::new($context)
}

function New-DependencyResolver {
    <#
    .SYNOPSIS
        Create a new DependencyResolver object
    #>
    return [DependencyResolver]::new()
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'New-ModuleManifest',
    'New-ModuleExecutor', 
    'New-ModuleExecutionResult',
    'New-DependencyResolver',
    'Write-Log'
)

# Note: Classes are automatically available when the module is imported in PowerShell 5.0+