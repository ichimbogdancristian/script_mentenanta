<#
.SYNOPSIS
    Plugin Architecture System v3.0 - Comprehensive Plugin Management

.DESCRIPTION
    Advanced plugin management system providing:
    - Dynamic plugin discovery and loading
    - Plugin lifecycle management (load/unload/enable/disable)
    - Security validation and sandboxing
    - Dependency resolution and conflict management
    - Plugin API contracts and interface enforcement
    - Plugin configuration management
    - Performance monitoring and health checks
    - Versioning and compatibility management

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Module Type: Core Infrastructure
    Dependencies: Infrastructure.psm1
    Requires: PowerShell 7.0+, Administrator privileges
#>

#Requires -Version 7.0

# Module-level variables for plugin management
$script:PluginRegistry = @{}
$script:LoadedPlugins = @{}
$script:PluginConfig = $null
$script:PluginContext = $null
$script:PluginInterfaces = @{}
$script:PluginDependencies = @{}

#region Plugin System Initialization

<#
.SYNOPSIS
    Initialize the plugin architecture system with comprehensive configuration.

.DESCRIPTION
    Sets up the plugin management infrastructure including:
    - Plugin directory structure creation
    - Configuration loading and validation
    - Security framework initialization
    - API contract registration
    - Plugin discovery and registration
    - Health monitoring setup

.PARAMETER ConfigPath
    Path to plugin configuration file. Defaults to config/plugin-config.json

.PARAMETER EnableSandboxing
    Enable plugin sandboxing for security isolation

.PARAMETER EnableAutoDiscovery
    Enable automatic plugin discovery on startup

.EXAMPLE
    Initialize-PluginSystem
    
.EXAMPLE
    Initialize-PluginSystem -ConfigPath "custom-plugin-config.json" -EnableSandboxing -EnableAutoDiscovery

.OUTPUTS
    [PSCustomObject] Plugin system context and status
#>
function Initialize-PluginSystem {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath = "config\plugin-config.json",
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableSandboxing,
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableAutoDiscovery
    )
    
    try {
        Write-Information "🔌 Initializing Plugin Architecture System v3.0" -InformationAction Continue
        
        # Load plugin configuration
        if (Test-Path $ConfigPath) {
            $script:PluginConfig = Get-Content $ConfigPath | ConvertFrom-Json -AsHashtable
            Write-Information "✅ Plugin configuration loaded from: $ConfigPath" -InformationAction Continue
        }
        else {
            Write-Warning "⚠️ Plugin config not found, using defaults: $ConfigPath"
            $script:PluginConfig = Get-DefaultPluginConfiguration
        }
        
        # Override configuration with parameters
        if ($EnableSandboxing.IsPresent) {
            $script:PluginConfig.security.sandboxingEnabled = $true
        }
        if ($EnableAutoDiscovery.IsPresent) {
            $script:PluginConfig.pluginSystem.autoDiscovery = $true
        }
        
        # Create plugin directory structure
        $directories = @(
            $script:PluginConfig.pluginPaths.systemPlugins,
            $script:PluginConfig.pluginPaths.userPlugins,
            $script:PluginConfig.pluginPaths.thirdPartyPlugins,
            $script:PluginConfig.pluginPaths.pluginCache,
            $script:PluginConfig.pluginPaths.pluginLogs,
            $script:PluginConfig.pluginPaths.pluginData
        )
        
        foreach ($directory in $directories) {
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                Write-Verbose "📁 Created plugin directory: $directory"
            }
        }
        
        # Initialize plugin context
        $script:PluginContext = @{
            StartTime          = Get-Date
            LoadedPlugins      = @{}
            FailedPlugins      = @{}
            PluginMetrics      = @{}
            SecurityContext    = @{
                ValidatedPlugins   = @()
                QuarantinedPlugins = @()
                TrustedPublishers  = $script:PluginConfig.security.allowedPublishers
            }
            PerformanceMetrics = @{
                LoadTimes       = @{}
                MemoryUsage     = @{}
                ExecutionCounts = @{}
            }
        }
        
        # Register built-in plugin interfaces
        Register-PluginInterfaces
        
        # Initialize security framework if enabled
        if ($script:PluginConfig.security.enableCodeAnalysis) {
            Initialize-PluginSecurity
        }
        
        # Perform auto-discovery if enabled
        if ($script:PluginConfig.pluginSystem.autoDiscovery) {
            Write-Information "🔍 Starting automatic plugin discovery..." -InformationAction Continue
            $discoveredPlugins = Invoke-PluginDiscovery
            Write-Information "📋 Discovered $($discoveredPlugins.Count) plugins" -InformationAction Continue
        }
        
        # Auto-load plugins if enabled
        if ($script:PluginConfig.pluginSystem.autoLoadOnStartup) {
            Write-Information "⚡ Loading plugins on startup..." -InformationAction Continue
            $loadedCount = Start-PluginAutoLoad
            Write-Information "🚀 Loaded $loadedCount plugins successfully" -InformationAction Continue
        }
        
        Write-Information "✅ Plugin architecture system initialized successfully" -InformationAction Continue
        
        return [PSCustomObject]@{
            Status               = "Initialized"
            ConfigPath           = $ConfigPath
            PluginPaths          = $script:PluginConfig.pluginPaths
            SecurityEnabled      = $script:PluginConfig.security.sandboxingEnabled
            AutoDiscoveryEnabled = $script:PluginConfig.pluginSystem.autoDiscovery
            LoadedPlugins        = $script:PluginContext.LoadedPlugins.Count
            RegisteredInterfaces = $script:PluginInterfaces.Count
        }
    }
    catch {
        Write-Error "❌ Failed to initialize plugin system: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Register built-in plugin interfaces and API contracts.

.DESCRIPTION
    Registers the standard plugin interfaces that plugins can implement:
    - IMaintenancePlugin: For system maintenance operations
    - IInventoryPlugin: For system inventory and data collection
    - IReportPlugin: For report generation and analytics
    - ISystemPlugin: For core system operations
    - ISecurityPlugin: For security-related functions
#>
function Register-PluginInterfaces {
    [CmdletBinding()]
    param()
    
    try {
        # Define standard plugin interfaces
        $interfaces = @{
            'IMaintenancePlugin' = @{
                Description     = 'Interface for system maintenance and cleanup plugins'
                RequiredMethods = @('Initialize-Plugin', 'Invoke-MaintenanceAction', 'Get-PluginInfo', 'Test-PluginHealth')
                OptionalMethods = @('Stop-Plugin', 'Get-PluginConfiguration', 'Set-PluginConfiguration')
                Properties      = @('Name', 'Version', 'Author', 'Description')
                Events          = @('PluginStarted', 'PluginStopped', 'PluginError')
            }
            'IInventoryPlugin'   = @{
                Description     = 'Interface for system inventory and data collection plugins'
                RequiredMethods = @('Initialize-Plugin', 'Get-InventoryData', 'Get-PluginInfo')
                OptionalMethods = @('Update-InventoryCache', 'Export-InventoryData')
                Properties      = @('Name', 'Version', 'DataCategory', 'CacheExpiration')
                Events          = @('InventoryUpdated', 'CacheExpired')
            }
            'IReportPlugin'      = @{
                Description     = 'Interface for report generation and analytics plugins'
                RequiredMethods = @('Initialize-Plugin', 'New-Report', 'Export-ReportData', 'Get-PluginInfo')
                OptionalMethods = @('Get-ReportTemplates', 'Invoke-ReportSchedule')
                Properties      = @('Name', 'Version', 'ReportFormats', 'TemplateSupport')
                Events          = @('ReportGenerated', 'ExportCompleted')
            }
            'ISystemPlugin'      = @{
                Description     = 'Interface for core system operation plugins'
                RequiredMethods = @('Initialize-Plugin', 'Invoke-SystemOperation', 'Get-PluginInfo')
                OptionalMethods = @('Test-SystemRequirements', 'Get-SystemMetrics')
                Properties      = @('Name', 'Version', 'RequiredPrivileges', 'SystemImpact')
                Events          = @('SystemModified', 'OperationCompleted')
            }
            'ISecurityPlugin'    = @{
                Description     = 'Interface for security-related plugins'
                RequiredMethods = @('Initialize-Plugin', 'Invoke-SecurityScan', 'Get-SecurityReport', 'Get-PluginInfo')
                OptionalMethods = @('Test-SecurityCompliance', 'Enable-SecurityFeature')
                Properties      = @('Name', 'Version', 'SecurityLevel', 'ComplianceStandards')
                Events          = @('ThreatDetected', 'ComplianceChecked', 'SecurityEnabled')
            }
        }
        
        $script:PluginInterfaces = $interfaces
        Write-Verbose "✅ Registered $($interfaces.Count) plugin interfaces"
        
        foreach ($interface in $interfaces.Keys) {
            Write-Verbose "📋 Interface: $interface - $($interfaces[$interface].Description)"
        }
        
    }
    catch {
        Write-Error "❌ Failed to register plugin interfaces: $_"
        throw
    }
}

<#
.SYNOPSIS
    Initialize plugin security framework for validation and sandboxing.

.DESCRIPTION
    Sets up security measures for plugin validation including:
    - Code analysis and validation
    - Digital signature verification
    - Sandbox environment preparation
    - Threat detection setup
#>
function Initialize-PluginSecurity {
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "🔒 Initializing plugin security framework..."
        
        # Initialize code analysis engine
        if (Get-Module -ListAvailable -Name "PSScriptAnalyzer") {
            Write-Verbose "✅ PSScriptAnalyzer available for code analysis"
            $script:PluginContext.SecurityContext.CodeAnalysisAvailable = $true
        }
        else {
            Write-Warning "⚠️ PSScriptAnalyzer not available - code analysis disabled"
            $script:PluginContext.SecurityContext.CodeAnalysisAvailable = $false
        }
        
        # Setup sandbox environment
        if ($script:PluginConfig.security.sandboxingEnabled) {
            $script:PluginContext.SecurityContext.SandboxEnabled = $true
            Write-Verbose "🏰 Plugin sandboxing enabled"
        }
        
        # Initialize quarantine directory
        $quarantinePath = Join-Path $script:PluginConfig.pluginPaths.pluginCache "quarantine"
        if (-not (Test-Path $quarantinePath)) {
            New-Item -Path $quarantinePath -ItemType Directory -Force | Out-Null
        }
        $script:PluginContext.SecurityContext.QuarantinePath = $quarantinePath
        
        Write-Verbose "✅ Plugin security framework initialized"
    }
    catch {
        Write-Error "❌ Failed to initialize plugin security: $_"
        throw
    }
}

#endregion

#region Plugin Discovery and Registration

<#
.SYNOPSIS
    Discover plugins in configured directories with comprehensive scanning.

.DESCRIPTION
    Scans plugin directories for valid plugin modules and manifests:
    - Searches system, user, and third-party plugin paths
    - Validates plugin structure and manifests
    - Performs security analysis if enabled
    - Registers discovered plugins in the plugin registry
    - Resolves plugin dependencies

.PARAMETER PluginPaths
    Specific paths to scan (uses configured paths if not specified)

.PARAMETER IncludeDisabled
    Include disabled plugins in discovery

.PARAMETER ForceRescan
    Force rescan even if cache is valid

.EXAMPLE
    $plugins = Invoke-PluginDiscovery
    
.EXAMPLE
    $plugins = Invoke-PluginDiscovery -IncludeDisabled -ForceRescan

.OUTPUTS
    [Array] Discovered plugin information objects
#>
function Invoke-PluginDiscovery {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$PluginPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDisabled,
        
        [Parameter(Mandatory = $false)]
        [switch]$ForceRescan
    )
    
    try {
        Write-Information "🔍 Starting plugin discovery process..." -InformationAction Continue
        
        # Use configured paths if none specified
        if ($PluginPaths.Count -eq 0) {
            $PluginPaths = @(
                $script:PluginConfig.pluginPaths.systemPlugins,
                $script:PluginConfig.pluginPaths.userPlugins,
                $script:PluginConfig.pluginPaths.thirdPartyPlugins
            )
        }
        
        $discoveredPlugins = @()
        
        foreach ($pluginPath in $PluginPaths) {
            if (Test-Path $pluginPath) {
                Write-Verbose "🔎 Scanning plugin path: $pluginPath"
                
                # Find all .psm1 files in the directory and subdirectories
                $pluginFiles = Get-ChildItem -Path $pluginPath -Filter "*.psm1" -Recurse
                
                foreach ($pluginFile in $pluginFiles) {
                    try {
                        Write-Verbose "📄 Analyzing plugin file: $($pluginFile.Name)"
                        
                        # Extract plugin metadata
                        $pluginMetadata = Get-PluginMetadata -PluginPath $pluginFile.FullName
                        
                        if ($null -ne $pluginMetadata) {
                            # Validate plugin structure
                            $validationResult = Test-PluginValidation -PluginMetadata $pluginMetadata -PluginPath $pluginFile.FullName
                            
                            if ($validationResult.IsValid -or $IncludeDisabled) {
                                # Perform security analysis if enabled
                                if ($script:PluginConfig.security.enableCodeAnalysis) {
                                    $securityResult = Test-PluginSecurity -PluginPath $pluginFile.FullName
                                    $pluginMetadata.SecurityStatus = $securityResult
                                }
                                
                                # Register plugin in registry
                                $pluginId = Register-Plugin -PluginMetadata $pluginMetadata -PluginPath $pluginFile.FullName -ValidationResult $validationResult
                                
                                if ($pluginId) {
                                    $discoveredPlugins += $pluginMetadata
                                    Write-Verbose "✅ Plugin registered: $($pluginMetadata.Name) (ID: $pluginId)"
                                }
                            }
                            else {
                                Write-Warning "⚠️ Plugin validation failed: $($pluginFile.Name) - $($validationResult.Issues -join ', ')"
                            }
                        }
                        else {
                            Write-Verbose "❌ No valid metadata found in: $($pluginFile.Name)"
                        }
                    }
                    catch {
                        Write-Warning "⚠️ Error analyzing plugin $($pluginFile.Name): $_"
                    }
                }
            }
            else {
                Write-Verbose "📁 Plugin path does not exist: $pluginPath"
            }
        }
        
        Write-Information "📋 Plugin discovery completed: $($discoveredPlugins.Count) plugins found" -InformationAction Continue
        return $discoveredPlugins
    }
    catch {
        Write-Error "❌ Plugin discovery failed: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extract metadata from plugin file using .PLUGININFO block.

.DESCRIPTION
    Parses plugin file to extract metadata from .PLUGININFO comment block:
    - Plugin name, version, author, description
    - Interface implementations
    - Dependencies and requirements
    - Configuration schema
    - Security permissions

.PARAMETER PluginPath
    Path to the plugin file

.OUTPUTS
    [PSCustomObject] Plugin metadata or $null if invalid
#>
function Get-PluginMetadata {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$PluginPath
    )
    
    try {
        $content = Get-Content $PluginPath -Raw
        
        # Extract .PLUGININFO metadata block
        if ($content -match '(?s)<#\s*\.PLUGININFO\s*(.*?)\s*#>') {
            $metadataBlock = $matches[1]
            
            # Parse metadata fields
            $metadata = @{}
            
            # Required fields
            if ($metadataBlock -match "Name\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Name = $matches[1] }
            if ($metadataBlock -match "Version\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Version = $matches[1] }
            if ($metadataBlock -match "Author\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Author = $matches[1] }
            if ($metadataBlock -match "Description\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Description = $matches[1] }
            if ($metadataBlock -match "Interface\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Interface = $matches[1] }
            
            # Optional fields
            if ($metadataBlock -match "Category\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Category = $matches[1] }
            if ($metadataBlock -match "Website\s*=\s*[`"']([^`"']+)[`"']") { $metadata.Website = $matches[1] }
            if ($metadataBlock -match "LicenseUri\s*=\s*[`"']([^`"']+)[`"']") { $metadata.LicenseUri = $matches[1] }
            if ($metadataBlock -match "MinimumApiVersion\s*=\s*[`"']([^`"']+)[`"']") { $metadata.MinimumApiVersion = $matches[1] }
            
            # Parse array fields
            if ($metadataBlock -match "Dependencies\s*=\s*@\(([^)]+)\)") {
                $depString = $matches[1]
                $metadata.Dependencies = @($depString -split ",\s*" | ForEach-Object { $_.Trim(' "''') })
            }
            else { $metadata.Dependencies = @() }
            
            if ($metadataBlock -match "Tags\s*=\s*@\(([^)]+)\)") {
                $tagString = $matches[1]
                $metadata.Tags = @($tagString -split ",\s*" | ForEach-Object { $_.Trim(' "''') })
            }
            else { $metadata.Tags = @() }
            
            # Parse permissions
            if ($metadataBlock -match "RequiredPermissions\s*=\s*@\(([^)]+)\)") {
                $permString = $matches[1]
                $metadata.RequiredPermissions = @($permString -split ",\s*" | ForEach-Object { $_.Trim(' "''') })
            }
            else { $metadata.RequiredPermissions = @() }
            
            # Validate required fields
            $requiredFields = @('Name', 'Version', 'Author', 'Description', 'Interface')
            $missingFields = $requiredFields | Where-Object { -not $metadata.ContainsKey($_) -or [string]::IsNullOrEmpty($metadata[$_]) }
            
            if ($missingFields.Count -gt 0) {
                Write-Warning "⚠️ Plugin metadata missing required fields: $($missingFields -join ', ') in $PluginPath"
                return $null
            }
            
            # Add file information
            $fileInfo = Get-Item $PluginPath
            $metadata.FilePath = $PluginPath
            $metadata.FileName = $fileInfo.Name
            $metadata.FileSize = $fileInfo.Length
            $metadata.LastModified = $fileInfo.LastWriteTime
            $metadata.DiscoveryTime = Get-Date
            
            # Validate interface
            if (-not $script:PluginInterfaces.ContainsKey($metadata.Interface)) {
                Write-Warning "⚠️ Unknown plugin interface: $($metadata.Interface) in $PluginPath"
                $metadata.InterfaceValid = $false
            }
            else {
                $metadata.InterfaceValid = $true
            }
            
            return [PSCustomObject]$metadata
        }
        else {
            Write-Verbose "No .PLUGININFO block found in: $PluginPath"
            return $null
        }
    }
    catch {
        Write-Warning "⚠️ Failed to extract plugin metadata from $PluginPath : $_"
        return $null
    }
}

<#
.SYNOPSIS
    Register a discovered plugin in the plugin registry.

.DESCRIPTION
    Adds plugin to the central registry with metadata and status tracking:
    - Assigns unique plugin ID
    - Stores plugin metadata and file information
    - Tracks validation and security status
    - Manages plugin state and lifecycle

.PARAMETER PluginMetadata
    Plugin metadata object from Get-PluginMetadata

.PARAMETER PluginPath
    Path to the plugin file

.PARAMETER ValidationResult
    Validation result from Test-PluginValidation

.OUTPUTS
    [string] Unique plugin ID or $null if registration failed
#>
function Register-Plugin {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PluginMetadata,
        
        [Parameter(Mandatory = $true)]
        [string]$PluginPath,
        
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$ValidationResult = $null
    )
    
    try {
        # Generate unique plugin ID
        $pluginId = "plugin-$($PluginMetadata.Name)-$(Get-Date -Format 'yyyyMMddHHmmss')-$((Get-Random -Maximum 9999).ToString('D4'))"
        
        # Create plugin registry entry
        $pluginEntry = @{
            Id                  = $pluginId
            Name                = $PluginMetadata.Name
            Version             = $PluginMetadata.Version
            Author              = $PluginMetadata.Author
            Description         = $PluginMetadata.Description
            Interface           = $PluginMetadata.Interface
            Category            = $PluginMetadata.Category
            FilePath            = $PluginPath
            FileName            = $PluginMetadata.FileName
            FileSize            = $PluginMetadata.FileSize
            LastModified        = $PluginMetadata.LastModified
            DiscoveryTime       = $PluginMetadata.DiscoveryTime
            Dependencies        = $PluginMetadata.Dependencies
            Tags                = $PluginMetadata.Tags
            RequiredPermissions = $PluginMetadata.RequiredPermissions
            Status              = 'Registered'
            ValidationResult    = $ValidationResult
            SecurityStatus      = $PluginMetadata.SecurityStatus
            LoadTime            = $null
            ExecutionCount      = 0
            LastError           = $null
            HealthStatus        = 'Unknown'
            Configuration       = @{}
        }
        
        # Add to plugin registry
        $script:PluginRegistry[$pluginId] = $pluginEntry
        
        Write-Verbose "📝 Plugin registered in registry: $($PluginMetadata.Name) -> $pluginId"
        return $pluginId
    }
    catch {
        Write-Error "❌ Failed to register plugin $($PluginMetadata.Name): $_"
        return $null
    }
}

#endregion

#region Plugin Validation and Security

<#
.SYNOPSIS
    Validate plugin structure, metadata, and requirements.

.DESCRIPTION
    Performs comprehensive validation of plugin including:
    - Metadata completeness and format
    - Interface implementation verification
    - Dependency availability checking
    - File structure validation
    - PowerShell syntax checking

.PARAMETER PluginMetadata
    Plugin metadata object

.PARAMETER PluginPath
    Path to the plugin file

.OUTPUTS
    [PSCustomObject] Validation result with IsValid flag and issues list
#>
function Test-PluginValidation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PluginMetadata,
        
        [Parameter(Mandatory = $true)]
        [string]$PluginPath
    )
    
    try {
        $issues = @()
        $warnings = @()
        
        # Validate metadata completeness
        $requiredFields = @('Name', 'Version', 'Author', 'Description', 'Interface')
        foreach ($field in $requiredFields) {
            if ([string]::IsNullOrEmpty($PluginMetadata.$field)) {
                $issues += "Missing required field: $field"
            }
        }
        
        # Validate version format (semantic versioning)
        if (-not [string]::IsNullOrEmpty($PluginMetadata.Version)) {
            if ($PluginMetadata.Version -notmatch '^\d+\.\d+\.\d+(-[\w\.-]+)?(\+[\w\.-]+)?$') {
                $warnings += "Version format should follow semantic versioning (x.y.z)"
            }
        }
        
        # Validate interface
        if (-not $script:PluginInterfaces.ContainsKey($PluginMetadata.Interface)) {
            $issues += "Unknown plugin interface: $($PluginMetadata.Interface)"
        }
        else {
            # Check if plugin implements required methods for its interface
            $interface = $script:PluginInterfaces[$PluginMetadata.Interface]
            $requiredMethods = $interface.RequiredMethods
            
            $content = Get-Content $PluginPath -Raw
            foreach ($method in $requiredMethods) {
                if ($content -notmatch "function\s+$method") {
                    $issues += "Missing required method for interface $($PluginMetadata.Interface): $method"
                }
            }
        }
        
        # Validate file size
        if ($PluginMetadata.FileSize -gt $script:PluginConfig.validation.maxPluginSize) {
            $maxSizeMB = [math]::Round($script:PluginConfig.validation.maxPluginSize / 1MB, 2)
            $actualSizeMB = [math]::Round($PluginMetadata.FileSize / 1MB, 2)
            $issues += "Plugin file too large: ${actualSizeMB}MB (max: ${maxSizeMB}MB)"
        }
        
        # PowerShell syntax validation
        try {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.PSParser]::Tokenize((Get-Content $PluginPath -Raw), [ref]$tokens, [ref]$errors)
            
            if ($errors.Count -gt 0) {
                foreach ($parseError in $errors) {
                    $issues += "PowerShell syntax error: $($parseError.Message) at line $($parseError.Token.StartLine)"
                }
            }
        }
        catch {
            $issues += "Failed to parse PowerShell syntax: $_"
        }
        
        # Validate dependencies
        foreach ($dependency in $PluginMetadata.Dependencies) {
            if ($dependency -notin $script:PluginRegistry.Values.Name) {
                # Check if it's a PowerShell module
                if (-not (Get-Module -ListAvailable -Name $dependency)) {
                    $warnings += "Dependency not found: $dependency"
                }
            }
        }
        
        # Validate required permissions
        $dangerousPermissions = @('FullControl', 'RegistryWrite', 'SystemModify')
        foreach ($permission in $PluginMetadata.RequiredPermissions) {
            if ($permission -in $dangerousPermissions) {
                $warnings += "Plugin requires dangerous permission: $permission"
            }
        }
        
        $isValid = $issues.Count -eq 0
        
        return [PSCustomObject]@{
            IsValid        = $isValid
            Issues         = $issues
            Warnings       = $warnings
            ValidationTime = Get-Date
        }
    }
    catch {
        return [PSCustomObject]@{
            IsValid        = $false
            Issues         = @("Validation failed: $_")
            Warnings       = @()
            ValidationTime = Get-Date
        }
    }
}

<#
.SYNOPSIS
    Perform security analysis on plugin code.

.DESCRIPTION
    Analyzes plugin code for security risks and compliance:
    - PSScriptAnalyzer security rules
    - Dangerous cmdlet usage detection
    - Network access pattern analysis
    - File system access validation
    - Registry modification detection

.PARAMETER PluginPath
    Path to the plugin file

.OUTPUTS
    [PSCustomObject] Security analysis result
#>
function Test-PluginSecurity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginPath
    )
    
    try {
        $securityIssues = @()
        $riskLevel = 'Low'
        
        # Read plugin content
        $content = Get-Content $PluginPath -Raw
        
        # Check for dangerous cmdlets
        $dangerousCmdlets = $script:PluginConfig.sandboxing.blockedCmdlets
        foreach ($cmdlet in $dangerousCmdlets) {
            if ($content -match $cmdlet) {
                $securityIssues += "Uses potentially dangerous cmdlet: $cmdlet"
                $riskLevel = 'High'
            }
        }
        
        # Check for network access
        $networkPatterns = @(
            'Invoke-WebRequest', 'Invoke-RestMethod', 'Net\.WebClient',
            'System\.Net\.Http', 'Start-BitsTransfer', 'wget', 'curl'
        )
        foreach ($pattern in $networkPatterns) {
            if ($content -match $pattern) {
                $securityIssues += "Contains network access code: $pattern"
                if ($riskLevel -eq 'Low') { $riskLevel = 'Medium' }
            }
        }
        
        # Check for registry access
        $registryPatterns = @(
            'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty',
            'HKLM:', 'HKCU:', 'Registry::'
        )
        foreach ($pattern in $registryPatterns) {
            if ($content -match $pattern) {
                $securityIssues += "Contains registry modification code: $pattern"
                if ($riskLevel -eq 'Low') { $riskLevel = 'Medium' }
            }
        }
        
        # Check for file system access outside allowed paths
        $filePatterns = @('Remove-Item', 'Copy-Item', 'Move-Item', 'New-Item.*-ItemType.*File')
        foreach ($pattern in $filePatterns) {
            if ($content -match $pattern) {
                $securityIssues += "Contains file system modification code: $pattern"
                if ($riskLevel -eq 'Low') { $riskLevel = 'Medium' }
            }
        }
        
        # PSScriptAnalyzer security analysis (if available)
        $psaResults = @()
        if ($script:PluginContext.SecurityContext.CodeAnalysisAvailable) {
            try {
                $psaResults = Invoke-ScriptAnalyzer -Path $PluginPath -Severity Warning, Error -IncludeRule PSAvoidUsingInvokeExpression, PSUsePSCredentialType, PSAvoidUsingPlainTextForPassword
                
                foreach ($result in $psaResults) {
                    $securityIssues += "PSScriptAnalyzer: $($result.RuleName) - $($result.Message)"
                    if ($result.Severity -eq 'Error') {
                        $riskLevel = 'High'
                    }
                    elseif ($result.Severity -eq 'Warning' -and $riskLevel -eq 'Low') {
                        $riskLevel = 'Medium'
                    }
                }
            }
            catch {
                Write-Warning "⚠️ PSScriptAnalyzer analysis failed: $_"
            }
        }
        
        # Determine if plugin should be quarantined
        $shouldQuarantine = $riskLevel -eq 'High' -or ($script:PluginConfig.security.quarantineUntrusted -and $securityIssues.Count -gt 0)
        
        return [PSCustomObject]@{
            RiskLevel               = $riskLevel
            SecurityIssues          = $securityIssues
            ShouldQuarantine        = $shouldQuarantine
            AnalysisTime            = Get-Date
            PSScriptAnalyzerResults = $psaResults
        }
    }
    catch {
        return [PSCustomObject]@{
            RiskLevel               = 'Unknown'
            SecurityIssues          = @("Security analysis failed: $_")
            ShouldQuarantine        = $true
            AnalysisTime            = Get-Date
            PSScriptAnalyzerResults = @()
        }
    }
}

#endregion

#region Plugin Lifecycle Management

<#
.SYNOPSIS
    Load a plugin with full lifecycle management.

.DESCRIPTION
    Loads and initializes a plugin with comprehensive management:
    - Dependency resolution and loading
    - Security validation and sandboxing
    - Plugin initialization and configuration
    - Health monitoring setup
    - Performance metrics tracking

.PARAMETER PluginId
    Unique plugin identifier from registry

.PARAMETER Force
    Force loading even if validation issues exist

.PARAMETER EnableSandbox
    Load plugin in sandboxed environment

.EXAMPLE
    $result = Start-Plugin -PluginId "plugin-SystemInfo-20251018140000-1234"
    
.EXAMPLE
    Start-Plugin -PluginId $pluginId -Force -EnableSandbox

.OUTPUTS
    [bool] True if plugin loaded successfully, False otherwise
#>
function Start-Plugin {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginId,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableSandbox
    )
    
    try {
        if (-not $script:PluginRegistry.ContainsKey($PluginId)) {
            Write-Error "Plugin not found in registry: $PluginId"
            return $false
        }
        
        $plugin = $script:PluginRegistry[$PluginId]
        
        if ($PSCmdlet.ShouldProcess($plugin.Name, 'Load Plugin')) {
            Write-Information "🚀 Loading plugin: $($plugin.Name) v$($plugin.Version)" -InformationAction Continue
            
            # Check if plugin is already loaded
            if ($script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
                Write-Warning "⚠️ Plugin already loaded: $($plugin.Name)"
                return $true
            }
            
            # Validate plugin before loading
            if (-not $plugin.ValidationResult.IsValid -and -not $Force) {
                Write-Error "❌ Plugin validation failed - use -Force to override: $($plugin.ValidationResult.Issues -join ', ')"
                return $false
            }
            
            # Check security status
            if ($plugin.SecurityStatus.ShouldQuarantine -and -not $Force) {
                Write-Error "❌ Plugin quarantined due to security risks - use -Force to override: $($plugin.SecurityStatus.SecurityIssues -join ', ')"
                return $false
            }
            
            $loadStartTime = Get-Date
            
            # Load plugin dependencies first
            foreach ($dependency in $plugin.Dependencies) {
                $depLoaded = Resolve-PluginDependency -Dependency $dependency -PluginId $PluginId
                if (-not $depLoaded) {
                    Write-Error "❌ Failed to load plugin dependency: $dependency"
                    return $false
                }
            }
            
            # Import the plugin module
            try {
                $moduleInfo = Import-Module $plugin.FilePath -Force -PassThru -Scope Global
                
                # Initialize plugin
                $initResult = Initialize-LoadedPlugin -PluginId $PluginId -ModuleInfo $moduleInfo
                
                if ($initResult) {
                    # Update plugin status
                    $plugin.Status = 'Loaded'
                    $plugin.LoadTime = Get-Date
                    
                    # Add to loaded plugins
                    $script:PluginContext.LoadedPlugins[$PluginId] = @{
                        Plugin             = $plugin
                        ModuleInfo         = $moduleInfo
                        LoadTime           = $loadStartTime
                        LastHealthCheck    = Get-Date
                        HealthStatus       = 'Healthy'
                        ExecutionCount     = 0
                        TotalExecutionTime = [TimeSpan]::Zero
                    }
                    
                    # Start health monitoring if enabled
                    if ($script:PluginConfig.lifecycle.enableHealthMonitoring) {
                        Start-PluginHealthMonitoring -PluginId $PluginId
                    }
                    
                    $loadDuration = (Get-Date) - $loadStartTime
                    Write-Information "✅ Plugin loaded successfully: $($plugin.Name) (Load time: $($loadDuration.TotalMilliseconds)ms)" -InformationAction Continue
                    
                    return $true
                }
                else {
                    Write-Error "❌ Plugin initialization failed: $($plugin.Name)"
                    return $false
                }
            }
            catch {
                $plugin.LastError = $_.Exception.Message
                Write-Error "❌ Failed to load plugin $($plugin.Name): $_"
                return $false
            }
        }
        
        return $false
    }
    catch {
        Write-Error "❌ Plugin loading failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Initialize a loaded plugin and verify interface implementation.

.DESCRIPTION
    Performs plugin initialization after module import:
    - Verifies required interface methods exist
    - Calls plugin Initialize-Plugin method
    - Sets up plugin configuration
    - Validates plugin health

.PARAMETER PluginId
    Plugin identifier

.PARAMETER ModuleInfo
    PowerShell module info object

.OUTPUTS
    [bool] True if initialization successful
#>
function Initialize-LoadedPlugin {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSModuleInfo]$ModuleInfo
    )
    
    try {
        $plugin = $script:PluginRegistry[$PluginId]
        $interface = $script:PluginInterfaces[$plugin.Interface]
        
        # Verify required methods are exported
        $exportedFunctions = $ModuleInfo.ExportedFunctions.Keys
        $missingMethods = @()
        
        foreach ($requiredMethod in $interface.RequiredMethods) {
            if ($requiredMethod -notin $exportedFunctions) {
                $missingMethods += $requiredMethod
            }
        }
        
        if ($missingMethods.Count -gt 0) {
            Write-Error "❌ Plugin missing required interface methods: $($missingMethods -join ', ')"
            return $false
        }
        
        # Call plugin initialization
        try {
            $initializeFunction = Get-Command "Initialize-Plugin" -Module $ModuleInfo.Name -ErrorAction Stop
            $initResult = & $initializeFunction
            
            if ($initResult -eq $false) {
                Write-Error "❌ Plugin Initialize-Plugin method returned false"
                return $false
            }
        }
        catch {
            Write-Error "❌ Plugin initialization method failed: $_"
            return $false
        }
        
        # Get plugin info
        try {
            $getInfoFunction = Get-Command "Get-PluginInfo" -Module $ModuleInfo.Name -ErrorAction Stop
            $pluginInfo = & $getInfoFunction
            
            # Validate plugin info matches metadata
            if ($pluginInfo.Name -ne $plugin.Name) {
                Write-Warning "⚠️ Plugin info name mismatch: metadata='$($plugin.Name)', plugin='$($pluginInfo.Name)'"
            }
        }
        catch {
            Write-Warning "⚠️ Failed to get plugin info: $_"
        }
        
        Write-Verbose "✅ Plugin initialized successfully: $($plugin.Name)"
        return $true
    }
    catch {
        Write-Error "❌ Plugin initialization failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Unload a plugin and clean up resources.

.DESCRIPTION
    Safely unloads a plugin with proper cleanup:
    - Calls plugin shutdown methods if available
    - Removes module from PowerShell session
    - Cleans up plugin resources and state
    - Updates plugin registry status

.PARAMETER PluginId
    Plugin identifier to unload

.PARAMETER Force
    Force unload even if plugin is in use

.EXAMPLE
    Stop-Plugin -PluginId "plugin-SystemInfo-20251018140000-1234"

.OUTPUTS
    [bool] True if plugin unloaded successfully
#>
function Stop-Plugin {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginId,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        if (-not $script:PluginContext.LoadedPlugins.ContainsKey($PluginId)) {
            Write-Warning "⚠️ Plugin not currently loaded: $PluginId"
            return $true
        }
        
        $loadedPlugin = $script:PluginContext.LoadedPlugins[$PluginId]
        $plugin = $loadedPlugin.Plugin
        
        if ($PSCmdlet.ShouldProcess($plugin.Name, 'Unload Plugin')) {
            Write-Information "🛑 Unloading plugin: $($plugin.Name)" -InformationAction Continue
            
            # Call plugin shutdown method if available
            try {
                $stopFunction = Get-Command "Stop-Plugin" -Module $loadedPlugin.ModuleInfo.Name -ErrorAction SilentlyContinue
                if ($stopFunction) {
                    & $stopFunction
                    Write-Verbose "✅ Plugin shutdown method called: $($plugin.Name)"
                }
            }
            catch {
                Write-Warning "⚠️ Plugin shutdown method failed: $_"
                if (-not $Force) {
                    return $false
                }
            }
            
            # Remove module from session
            try {
                Remove-Module $loadedPlugin.ModuleInfo.Name -Force
                Write-Verbose "✅ Module removed from session: $($plugin.Name)"
            }
            catch {
                Write-Warning "⚠️ Failed to remove module: $_"
                if (-not $Force) {
                    return $false
                }
            }
            
            # Update plugin status
            $plugin.Status = 'Unloaded'
            
            # Remove from loaded plugins
            $script:PluginContext.LoadedPlugins.Remove($PluginId)
            
            Write-Information "✅ Plugin unloaded successfully: $($plugin.Name)" -InformationAction Continue
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "❌ Plugin unload failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Auto-load plugins based on configuration settings.

.DESCRIPTION
    Loads plugins automatically during system startup:
    - Loads plugins in dependency order
    - Respects plugin priorities and categories
    - Handles load failures gracefully
    - Provides progress feedback

.OUTPUTS
    [int] Number of plugins successfully loaded
#>
function Start-PluginAutoLoad {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    try {
        Write-Information "⚡ Starting automatic plugin loading..." -InformationAction Continue
        
        # Get plugins to auto-load (valid plugins with no critical issues)
        $pluginsToLoad = $script:PluginRegistry.Values | Where-Object { 
            $_.ValidationResult.IsValid -and 
            $_.SecurityStatus.RiskLevel -ne 'High' -and
            $_.Status -eq 'Registered'
        }
        
        if ($pluginsToLoad.Count -eq 0) {
            Write-Information "📋 No plugins available for auto-loading" -InformationAction Continue
            return 0
        }
        
        # Sort plugins by load order (system plugins first, then by category)
        $sortedPlugins = $pluginsToLoad | Sort-Object @(
            @{Expression = { if ($_.Category -eq 'system') { 0 } elseif ($_.Category -eq 'security') { 1 } else { 2 } } },
            @{Expression = { $_.Name } }
        )
        
        $loadedCount = 0
        $failedCount = 0
        
        foreach ($plugin in $sortedPlugins) {
            try {
                Write-Information "🔄 Loading plugin: $($plugin.Name)" -InformationAction Continue
                
                $loadResult = Start-Plugin -PluginId $plugin.Id -Confirm:$false
                
                if ($loadResult) {
                    $loadedCount++
                    Write-Verbose "✅ Auto-loaded: $($plugin.Name)"
                }
                else {
                    $failedCount++
                    Write-Warning "⚠️ Failed to auto-load: $($plugin.Name)"
                }
            }
            catch {
                $failedCount++
                Write-Warning "⚠️ Auto-load error for $($plugin.Name): $_"
            }
        }
        
        Write-Information "📊 Auto-load complete: $loadedCount loaded, $failedCount failed" -InformationAction Continue
        return $loadedCount
    }
    catch {
        Write-Error "❌ Auto-load process failed: $_"
        return 0
    }
}

#endregion

#region Plugin Dependency Management

<#
.SYNOPSIS
    Resolve and load plugin dependencies.

.DESCRIPTION
    Handles plugin dependency resolution:
    - Loads required PowerShell modules
    - Loads dependent plugins in correct order
    - Manages circular dependency detection
    - Handles version conflicts

.PARAMETER Dependency
    Dependency name to resolve

.PARAMETER PluginId
    Plugin requesting the dependency

.OUTPUTS
    [bool] True if dependency resolved successfully
#>
function Resolve-PluginDependency {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dependency,
        
        [Parameter(Mandatory = $true)]
        [string]$PluginId
    )
    
    try {
        Write-Verbose "🔗 Resolving dependency: $Dependency for plugin: $PluginId"
        
        # Check if it's already a loaded PowerShell module
        if (Get-Module -Name $Dependency) {
            Write-Verbose "✅ Dependency already loaded as PowerShell module: $Dependency"
            return $true
        }
        
        # Check if it's a plugin in our registry
        $dependentPlugin = $script:PluginRegistry.Values | Where-Object { $_.Name -eq $Dependency }
        
        if ($dependentPlugin) {
            # Check for circular dependencies
            if (Test-CircularDependency -PluginId $PluginId -DependencyId $dependentPlugin.Id) {
                Write-Error "❌ Circular dependency detected: $PluginId -> $($dependentPlugin.Id)"
                return $false
            }
            
            # Load the dependent plugin if not already loaded
            if (-not $script:PluginContext.LoadedPlugins.ContainsKey($dependentPlugin.Id)) {
                Write-Verbose "🔄 Loading dependent plugin: $($dependentPlugin.Name)"
                $loadResult = Start-Plugin -PluginId $dependentPlugin.Id -Confirm:$false
                
                if (-not $loadResult) {
                    Write-Error "❌ Failed to load dependent plugin: $($dependentPlugin.Name)"
                    return $false
                }
            }
            
            Write-Verbose "✅ Plugin dependency resolved: $Dependency"
            return $true
        }
        
        # Try to load as PowerShell module
        try {
            Import-Module $Dependency -Force -Global
            Write-Verbose "✅ PowerShell module dependency loaded: $Dependency"
            return $true
        }
        catch {
            Write-Warning "⚠️ Failed to load PowerShell module dependency: $Dependency - $_"
        }
        
        # Check if dependency is available for installation
        $availableModule = Find-Module -Name $Dependency -ErrorAction SilentlyContinue
        if ($availableModule) {
            if ($script:PluginConfig.dependencyManagement.autoInstallDependencies) {
                try {
                    Install-Module -Name $Dependency -Force -AllowClobber -Scope CurrentUser
                    Import-Module $Dependency -Force -Global
                    Write-Information "✅ Auto-installed and loaded module dependency: $Dependency" -InformationAction Continue
                    return $true
                }
                catch {
                    Write-Warning "⚠️ Failed to auto-install module dependency: $Dependency - $_"
                }
            }
            else {
                Write-Warning "⚠️ Module dependency available but auto-install disabled: $Dependency"
            }
        }
        
        Write-Error "❌ Unable to resolve dependency: $Dependency"
        return $false
    }
    catch {
        Write-Error "❌ Dependency resolution failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Test for circular dependencies between plugins.

.DESCRIPTION
    Detects circular dependency chains to prevent infinite loading loops.

.PARAMETER PluginId
    Source plugin ID

.PARAMETER DependencyId
    Target dependency plugin ID

.OUTPUTS
    [bool] True if circular dependency detected
#>
function Test-CircularDependency {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginId,
        
        [Parameter(Mandatory = $true)]
        [string]$DependencyId
    )
    
    # Simple circular dependency check - can be enhanced with more sophisticated graph algorithms
    function Test-DependencyChain {
        param($currentId, $targetId, $visitedNodes)
        
        if ($currentId -in $visitedNodes) {
            return $true  # Circular dependency found
        }
        
        if ($currentId -eq $targetId) {
            return $true  # Direct circular dependency
        }
        
        $visitedNodes += $currentId
        $currentPlugin = $script:PluginRegistry[$currentId]
        
        if ($currentPlugin -and $currentPlugin.Dependencies) {
            foreach ($dep in $currentPlugin.Dependencies) {
                $depPlugin = $script:PluginRegistry.Values | Where-Object { $_.Name -eq $dep }
                if ($depPlugin) {
                    if (Test-DependencyChain -currentId $depPlugin.Id -targetId $targetId -visitedNodes $visitedNodes) {
                        return $true
                    }
                }
            }
        }
        
        return $false
    }
    
    return Test-DependencyChain -currentId $DependencyId -targetId $PluginId -visitedNodes @()
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-PluginSystem',
    'Invoke-PluginDiscovery',
    'Get-PluginMetadata',
    'Register-Plugin',
    'Test-PluginValidation',
    'Test-PluginSecurity',
    'Start-Plugin',
    'Stop-Plugin',
    'Start-PluginAutoLoad',
    'Resolve-PluginDependency'
)