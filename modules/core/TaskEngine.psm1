<#
.SYNOPSIS
    Task engine module for Windows Maintenance Automation v3.0

.DESCRIPTION
    Handles automatic module discovery, task registration, and execution pipeline.
    Supports auto-discovery of Type2 modules with .MODULEINFO metadata and
    coordinates Type1 inventory + Type2 action execution.

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Requires: PowerShell 7.0+, Infrastructure.psm1
#>

#Requires -Version 7.0

# Module-level variables
$script:TaskRegistry = @()
$script:DiscoveredModules = @{}

<#
.SYNOPSIS
    Parses .MODULEINFO metadata block from a PowerShell module file.

.DESCRIPTION
    Extracts metadata from comment block at the beginning of .psm1 files.
    Metadata format:
    .MODULEINFO
    Type = "Type2"
    Category = "Apps"
    MenuText = "Remove Bloatware"
    Description = "Removes unwanted applications"
    InventoryModule = "AppsInventory.psm1"
    ConfigFiles = @("bloatware-list.json")
    DependsOn = @("Infrastructure")

.PARAMETER ModulePath
    Path to the .psm1 file to parse.

.OUTPUTS
    Hashtable with metadata properties or $null if not found.

.EXAMPLE
    $metadata = Get-TaskMetadata -ModulePath "modules\type2\BloatwareRemoval.psm1"
#>
function Get-TaskMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ModulePath
    )
    
    try {
        $content = Get-Content $ModulePath -Raw
        
        # Look for .MODULEINFO block in comments
        if ($content -match '(?s)<#\s*\.MODULEINFO\s*(.*?)\s*#>') {
            $metadataBlock = $Matches[1]
            
            $metadata = @{
                Type            = ''
                Category        = ''
                MenuText        = ''
                Description     = ''
                InventoryModule = ''
                ConfigFiles     = @()
                DependsOn       = @()
                ModulePath      = $ModulePath
                ModuleName      = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)
            }
            
            # Parse each property using simpler regex patterns
            if ($metadataBlock -match 'Type\s*=\s*"([^"]+)"') {
                $metadata.Type = $Matches[1]
            }
            if ($metadataBlock -match 'Category\s*=\s*"([^"]+)"') {
                $metadata.Category = $Matches[1]
            }
            if ($metadataBlock -match 'MenuText\s*=\s*"([^"]+)"') {
                $metadata.MenuText = $Matches[1]
            }
            if ($metadataBlock -match 'Description\s*=\s*"([^"]+)"') {
                $metadata.Description = $Matches[1]
            }
            if ($metadataBlock -match 'InventoryModule\s*=\s*"([^"]+)"') {
                $metadata.InventoryModule = $Matches[1]
            }
            if ($metadataBlock -match 'ConfigFiles\s*=\s*@\(([^)]+)\)') {
                $configFiles = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"') }
                $metadata.ConfigFiles = $configFiles
            }
            if ($metadataBlock -match 'DependsOn\s*=\s*@\(([^)]+)\)') {
                $deps = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"') }
                $metadata.DependsOn = $deps
            }
            
            return $metadata
        }
        else {
            Write-Verbose "No .MODULEINFO block found in $ModulePath"
            return $null
        }
    }
    catch {
        Write-Error "Failed to parse metadata from $ModulePath : $_"
        return $null
    }
}

<#
.SYNOPSIS
    Discovers and registers all Type1 and Type2 modules.

.DESCRIPTION
    Scans modules/type1/ and modules/type2/ directories for modules with .MODULEINFO metadata.
    Builds a registry of available tasks for menu display and execution.

.PARAMETER ScriptRoot
    Script root directory for path resolution.

.OUTPUTS
    Array of task hashtables with metadata.

.EXAMPLE
    $tasks = Register-ModuleTasks -ScriptRoot $PSScriptRoot
#>
function Register-ModuleTasks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptRoot = $PSScriptRoot
    )
    
    begin {
        Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message 'Starting module discovery'
    }
    
    process {
        try {
            $modulesRoot = Join-Path $ScriptRoot "modules"
            $type1Path = Join-Path $modulesRoot "type1"
            $type2Path = Join-Path $modulesRoot "type2"
            
            # Collect all module files from both directories
            $moduleFiles = @()
            
            if (Test-Path $type1Path) {
                $moduleFiles += Get-ChildItem -Path $type1Path -Filter "*.psm1" -File
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Found $(@(Get-ChildItem -Path $type1Path -Filter '*.psm1' -File).Count) Type1 modules"
            }
            
            if (Test-Path $type2Path) {
                $moduleFiles += Get-ChildItem -Path $type2Path -Filter "*.psm1" -File
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Found $(@(Get-ChildItem -Path $type2Path -Filter '*.psm1' -File).Count) Type2 modules"
            }
            
            if ($moduleFiles.Count -eq 0) {
                Write-DetailedLog -Level 'WARNING' -Component 'TASKENGINE' -Message "No modules found in type1/ or type2/ directories"
                return @()
            }
            
            $tasks = @()
            
            Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Found $($moduleFiles.Count) module files to scan"
            
            foreach ($moduleFile in $moduleFiles) {
                Write-Verbose "Scanning: $($moduleFile.FullName)"
                
                $metadata = Get-TaskMetadata -ModulePath $moduleFile.FullName
                
                if ($metadata -and $metadata.Type -eq 'Type2') {
                    # This is a task module (Type2 = action module)
                    $task = @{
                        Name            = $metadata.ModuleName
                        MenuText        = $metadata.MenuText
                        Description     = $metadata.Description
                        Category        = $metadata.Category
                        ModulePath      = $moduleFile.FullName
                        InventoryModule = $metadata.InventoryModule
                        ConfigFiles     = $metadata.ConfigFiles
                        DependsOn       = $metadata.DependsOn
                        Type            = 'Type2'
                    }
                    
                    $tasks += $task
                    $script:DiscoveredModules[$metadata.ModuleName] = $moduleFile.FullName
                    
                    Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Registered task: $($metadata.MenuText) [$($metadata.Category)]"
                }
                elseif ($metadata -and $metadata.Type -eq 'Type1') {
                    # Inventory module - store for later use
                    $script:DiscoveredModules[$metadata.ModuleName] = $moduleFile.FullName
                    Write-Verbose "Registered inventory module: $($metadata.ModuleName)"
                }
            }
            
            # Sort tasks by category and name
            $tasks = $tasks | Sort-Object Category, MenuText
            
            $script:TaskRegistry = $tasks
            
            Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Discovered $($tasks.Count) tasks across $($moduleFiles.Count) modules"
            
            return $tasks
        }
        catch {
            Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message "Module discovery failed: $_" -Exception $_
            return @()
        }
    }
}

<#
.SYNOPSIS
    Gets the current task registry.

.DESCRIPTION
    Returns the array of discovered tasks. Supports filtering by category.

.PARAMETER Category
    Optional category filter (Apps, Updates, Privacy, System, Security).

.OUTPUTS
    Array of task hashtables.

.EXAMPLE
    $allTasks = Get-TaskRegistry
    $appsTasks = Get-TaskRegistry -Category 'Apps'
#>
function Get-TaskRegistry {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('', 'Apps', 'Updates', 'Privacy', 'System', 'Security')]
        [string]$Category = ''
    )
    
    if ($Category) {
        return $script:TaskRegistry | Where-Object { $_.Category -eq $Category }
    }
    else {
        return $script:TaskRegistry
    }
}

<#
.SYNOPSIS
    Executes a task with full Type1/Type2 pipeline.

.DESCRIPTION
    Executes maintenance task with automatic inventory management:
    1. Load/import inventory module (Type1)
    2. Run pre-check inventory scan
    3. Execute action module (Type2)
    4. Run post-check inventory scan
    5. Compare before/after and log changes

.PARAMETER Task
    Task hashtable from task registry.

.PARAMETER DryRun
    If specified, performs dry-run (simulates without making changes).

.PARAMETER OpId
    Operation ID for tracking (auto-generated if not provided).

.OUTPUTS
    Hashtable with execution results (Success, Message, Data).

.EXAMPLE
    $result = Invoke-TaskWithInventory -Task $task -DryRun
    
.EXAMPLE
    $tasks = Get-TaskRegistry
    foreach ($task in $tasks) {
        Invoke-TaskWithInventory -Task $task
    }
#>
function Invoke-TaskWithInventory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Task,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun,
        
        [Parameter(Mandatory = $false)]
        [string]$OpId = ''
    )
    
    begin {
        if (-not $OpId) {
            $OpId = New-OperationId
        }
    }
    
    process {
        $perf = Start-PerformanceTracking -OperationName $Task.Name -Component 'TASKENGINE'
        
        try {
            Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Executing task: $($Task.MenuText)" -OpId $OpId
            
            $result = @{
                Success         = $false
                Message         = ''
                TaskName        = $Task.Name
                Category        = $Task.Category
                OpId            = $OpId
                Data            = @{}
                InventoryBefore = $null
                InventoryAfter  = $null
            }
            
            # Step 1: Load inventory module if specified
            $inventoryModule = $null
            if ($Task.InventoryModule) {
                $inventoryModuleName = [System.IO.Path]::GetFileNameWithoutExtension($Task.InventoryModule)
                
                if ($script:DiscoveredModules.ContainsKey($inventoryModuleName)) {
                    $inventoryModulePath = $script:DiscoveredModules[$inventoryModuleName]
                    
                    Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Loading inventory module: $inventoryModuleName" -OpId $OpId
                    
                    try {
                        Import-Module $inventoryModulePath -Force -ErrorAction Stop
                        $inventoryModule = Get-Module $inventoryModuleName
                        Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Inventory module loaded: $inventoryModuleName" -OpId $OpId
                    }
                    catch {
                        Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message "Failed to load inventory module: $_" -OpId $OpId -Exception $_
                    }
                }
            }
            
            # Step 2: Run pre-check inventory (if inventory module available)
            if ($inventoryModule) {
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Running pre-check inventory scan" -OpId $OpId
                
                try {
                    # Call Get-*Inventory function
                    $inventoryFunction = "Get-$($Task.Category)Inventory"
                    if (Get-Command $inventoryFunction -ErrorAction SilentlyContinue) {
                        $result.InventoryBefore = & $inventoryFunction
                        Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Pre-check inventory completed" -OpId $OpId
                    }
                }
                catch {
                    Write-DetailedLog -Level 'WARNING' -Component 'TASKENGINE' -Message "Pre-check inventory failed: $_" -OpId $OpId
                }
            }
            
            # Step 3: Load and execute action module (Type2)
            Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Loading action module: $($Task.Name)" -OpId $OpId
            
            try {
                Import-Module $Task.ModulePath -Force -ErrorAction Stop
                Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Action module loaded" -OpId $OpId
            }
            catch {
                $result.Message = "Failed to load action module: $_"
                Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message $result.Message -OpId $OpId -Exception $_
                Complete-PerformanceTracking -PerformanceContext $perf -Success $false
                return $result
            }
            
            # Execute main function from action module
            Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Executing action: $($Task.Name)" -OpId $OpId
            
            if ($PSCmdlet.ShouldProcess($Task.MenuText, "Execute maintenance task")) {
                try {
                    # Get exported functions from module
                    $actionModule = Get-Module $Task.Name
                    if ($actionModule) {
                        $exportedCommands = $actionModule.ExportedCommands.Keys
                        
                        # Try to find main action function (usually starts with verb like Remove-, Install-, Set-, etc.)
                        $mainFunction = $exportedCommands | Where-Object { 
                            $_ -match '^(Remove|Install|Set|Enable|Disable|Optimize|Update)-' 
                        } | Select-Object -First 1
                        
                        if ($mainFunction) {
                            Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Invoking function: $mainFunction" -OpId $OpId
                            
                            # Execute with parameters
                            $functionParams = @{
                                Confirm = $false  # Disable confirmation prompts for automation
                            }
                            
                            if ($DryRun) {
                                $functionParams['WhatIf'] = $true
                            }
                            
                            $actionResult = & $mainFunction @functionParams
                            
                            $result.Success = if ($actionResult -is [bool]) { $actionResult } else { $true }
                            $result.Data['ActionResult'] = $actionResult
                            
                            # Log based on actual result
                            if ($result.Success) {
                                Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Action completed successfully" -OpId $OpId
                            }
                            else {
                                Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message "Action failed - module returned false" -OpId $OpId
                            }
                        }
                        else {
                            Write-DetailedLog -Level 'WARNING' -Component 'TASKENGINE' -Message "No main action function found in module" -OpId $OpId
                            $result.Success = $true
                            $result.Message = "Module loaded but no action function found"
                        }
                    }
                }
                catch {
                    $result.Message = "Action execution failed: $_"
                    Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message $result.Message -OpId $OpId -Exception $_
                    Complete-PerformanceTracking -PerformanceContext $perf -Success $false
                    return $result
                }
            }
            else {
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Action skipped (WhatIf mode)" -OpId $OpId
                $result.Success = $true
                $result.Message = "Skipped (WhatIf mode)"
            }
            
            # Step 4: Run post-check inventory (if inventory module available)
            if ($inventoryModule -and -not $DryRun) {
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Running post-check inventory scan" -OpId $OpId
                
                try {
                    $inventoryFunction = "Get-$($Task.Category)Inventory"
                    if (Get-Command $inventoryFunction -ErrorAction SilentlyContinue) {
                        $result.InventoryAfter = & $inventoryFunction
                        Write-DetailedLog -Level 'SUCCESS' -Component 'TASKENGINE' -Message "Post-check inventory completed" -OpId $OpId
                    }
                }
                catch {
                    Write-DetailedLog -Level 'WARNING' -Component 'TASKENGINE' -Message "Post-check inventory failed: $_" -OpId $OpId
                }
            }
            
            # Step 5: Compare inventories and log changes
            if ($result.InventoryBefore -and $result.InventoryAfter) {
                Write-DetailedLog -Level 'INFO' -Component 'TASKENGINE' -Message "Comparing before/after inventory" -OpId $OpId
                # Comparison logic would go here - for now just log that we have both
                $result.Data['InventoryComparison'] = 'Available'
            }
            
            # Set default message based on success status
            if (-not $result.Message) {
                $result.Message = if ($result.Success) { "Task completed successfully" } else { "Task completed with errors" }
            }
            
            Complete-PerformanceTracking -PerformanceContext $perf -Success $result.Success -ResultData $result.Data
            
            return $result
        }
        catch {
            Write-DetailedLog -Level 'ERROR' -Component 'TASKENGINE' -Message "Task execution failed: $_" -OpId $OpId -Exception $_
            Complete-PerformanceTracking -PerformanceContext $perf -Success $false
            
            return @{
                Success  = $false
                Message  = "Execution failed: $_"
                TaskName = $Task.Name
                Category = $Task.Category
                OpId     = $OpId
                Data     = @{}
            }
        }
    }
}

# Export all public functions
Export-ModuleMember -Function @(
    'Get-TaskMetadata',
    'Register-ModuleTasks',
    'Get-TaskRegistry',
    'Invoke-TaskWithInventory'
)
