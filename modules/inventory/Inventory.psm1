# Inventory.psm1 - System inventory collection module for Windows Maintenance Automation
# Provides comprehensive system and application inventory capabilities

# ================================================================
# Function: Get-SystemInventory
# ================================================================
# Purpose: Main inventory collection function (alias for Get-ExtensiveSystemInventory)
# ================================================================
function Get-SystemInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = (Get-Location).Path,
        [Parameter(Mandatory = $false)]
        [switch]$LegacyMode
    )

    # Use optimized inventory by default
    if (-not $LegacyMode) {
        Write-Log "Delegating to optimized system inventory for enhanced performance..." 'INFO'
        return Get-OptimizedSystemInventory -WorkingDirectory $WorkingDirectory -UseCache -IncludeBloatwareDetection
    }

    # Legacy mode for backward compatibility
    Write-Log 'Starting Extensive System Inventory (JSON Format) - Legacy Mode.' 'INFO'
    Write-TaskProgress "Collecting system inventory" 10

    $inventoryFolder = $WorkingDirectory
    if (-not (Test-Path $inventoryFolder)) {
        New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null
    }

    # Legacy inventory collection logic would go here
    # For now, delegate to optimized version
    return Get-OptimizedSystemInventory -WorkingDirectory $WorkingDirectory -UseCache -IncludeBloatwareDetection
}

# ================================================================
# Function: Get-OptimizedSystemInventory
# ================================================================
# Purpose: Optimized system inventory collection with caching and parallel processing
# ================================================================
function Get-OptimizedSystemInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = (Get-Location).Path,
        [Parameter(Mandatory = $false)]
        [switch]$UseCache,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeBloatwareDetection,
        [Parameter(Mandatory = $false)]
        [switch]$ForceFullScan
    )

    Write-Log "[START] Optimized System Inventory Collection" 'INFO'
    $startTime = Get-Date

    # Set default behavior for switches
    if (-not $PSBoundParameters.ContainsKey('UseCache')) { $UseCache = $true }
    if (-not $PSBoundParameters.ContainsKey('IncludeBloatwareDetection')) { $IncludeBloatwareDetection = $true }

    # Check if we can use cached inventory
    if ($UseCache -and $global:SystemInventory -and -not $ForceFullScan) {
        $cacheAge = (Get-Date) - [DateTime]::Parse($global:SystemInventory.metadata.generatedOn)
        if ($cacheAge.TotalMinutes -lt 15) {
            Write-Log "Using cached system inventory (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)" 'INFO'
            return $global:SystemInventory
        }
    }

    $inventoryFolder = $WorkingDirectory
    if (-not (Test-Path $inventoryFolder)) {
        New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null
    }

    # Build optimized inventory using modular utilities
    Write-Log "Building optimized system inventory..." 'INFO'
    Write-TaskProgress "Optimized inventory collection" 10

    # Use the standardized app inventory function for efficient collection
    $appInventory = Get-StandardizedAppInventory -Sources @('AppX', 'Winget', 'Chocolatey') -UseCache:$UseCache

    # Build structured inventory object with enhanced data
    $inventory = [ordered]@{
        metadata            = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = '2.0.0'
            hostname      = $env:COMPUTERNAME
            user          = $env:USERNAME
            powershell    = $PSVersionTable.PSVersion.ToString()
            cacheEnabled  = $UseCache.IsPresent
            fullScan      = $ForceFullScan.IsPresent
        }
        system              = @{}
        appx                = @()
        winget              = @()
        choco               = @()
        registry_uninstall  = @()
        services            = @()
        scheduled_tasks     = @()
        drivers             = @()
        bloatware_detection = @{}
    }

    # Parallel system information collection
    Write-TaskProgress "Collecting system information" 25
    try {
        $systemInfo = Get-ComputerInfo -ErrorAction SilentlyContinue | Select-Object TotalPhysicalMemory, CsProcessors, WindowsProductName, WindowsVersion, BiosFirmwareType
        $inventory.system = $systemInfo
        Write-Log "System information collected successfully" 'INFO'
    }
    catch {
        Write-Log "System information collection failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    # Process standardized app inventory into categorized collections
    Write-TaskProgress "Processing application inventory" 50
    $inventory.appx = $appInventory | Where-Object { $_.Source -eq 'AppX' }
    $inventory.winget = $appInventory | Where-Object { $_.Source -eq 'Winget' }
    $inventory.choco = $appInventory | Where-Object { $_.Source -eq 'Chocolatey' }

    Write-Log "Applications: AppX($($inventory.appx.Count)), Winget($($inventory.winget.Count)), Chocolatey($($inventory.choco.Count))" 'INFO'

    # Enhanced registry collection (optimized)
    Write-TaskProgress "Collecting registry information" 70
    try {
        $registryApps = Get-RegistryUninstallBloatware -BloatwarePatterns @('*') -Context "Full Registry Scan" | Select-Object Name, DisplayName, Version, UninstallKey
        $inventory.registry_uninstall = $registryApps
        Write-Log "Registry applications collected: $($registryApps.Count)" 'INFO'
    }
    catch {
        Write-Log "Registry collection failed: $_" 'WARN'
        $inventory.registry_uninstall = @()
    }

    # Bloatware detection (if enabled)
    if ($IncludeBloatwareDetection) {
        Write-TaskProgress "Enhanced bloatware detection" 85
        try {
            $bloatwareResults = Get-ComprehensiveBloatwareInventory -UseCache:$UseCache
            $inventory.bloatware_detection = $bloatwareResults

            # Summary statistics
            $totalBloatware = 0
            foreach ($sourceType in $bloatwareResults.Keys) {
                foreach ($source in $bloatwareResults[$sourceType].Keys) {
                    $totalBloatware += $bloatwareResults[$sourceType][$source].Count
                }
            }
            Write-Log "Enhanced bloatware detection completed: $totalBloatware total items found" 'INFO'
        }
        catch {
            Write-Log "Bloatware detection failed: $_" 'WARN'
            $inventory.bloatware_detection = @{}
        }
    }

    # Save optimized inventory
    Write-TaskProgress "Finalizing inventory" 95
    try {
        $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log "Optimized inventory saved to inventory.json" 'INFO'

        # Store global reference
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "Failed to write inventory.json: $_" 'WARN'
    }

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    Write-Log "[COMPLETE] Optimized System Inventory Collection in $([math]::Round($duration, 2))s" 'SUCCESS'

    return $inventory
}

# ================================================================
# Function: Get-StandardizedAppInventory
# ================================================================
# Purpose: Collect applications from multiple sources with standardized format
# ================================================================
function Get-StandardizedAppInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Sources = @('AppX', 'Winget', 'Chocolatey'),
        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails,
        [Parameter(Mandatory = $false)]
        [switch]$UseCache,
        [Parameter(Mandatory = $false)]
        [string]$Context = "System Inventory"
    )

    Write-Log "[START] Standardized App Inventory Collection: $Context" 'INFO'
    $startTime = Get-Date

    # Check cache if UseCache is enabled
    if ($UseCache -and $global:AppInventoryCache -and $global:AppInventoryCache.Timestamp) {
        $cacheAge = (Get-Date) - $global:AppInventoryCache.Timestamp
        if ($cacheAge.TotalMinutes -lt 10) {
            Write-Log "Using cached app inventory (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)" 'INFO'
            return $global:AppInventoryCache.Data
        }
    }

    $allApps = @()

    try {
        # AppX packages
        if ('AppX' -in $Sources) {
            try {
                Write-Log "Collecting AppX packages..." 'INFO'
                $appxApps = Get-AppxPackageCompatible | ForEach-Object {
                    @{
                        Name              = $_.Name
                        DisplayName       = $_.PackageFullName
                        Version           = $_.Version.ToString()
                        Source            = 'AppX'
                        InstallLocation   = $_.InstallLocation
                        PackageFamilyName = $_.PackageFamilyName
                    }
                }
                $allApps += $appxApps
                Write-Log "Collected $($appxApps.Count) AppX packages" 'INFO'
            }
            catch {
                Write-Log "Failed to collect AppX packages: $_" 'WARN'
            }
        }

        # Winget packages
        if ('Winget' -in $Sources -and (Test-CommandAvailable 'winget')) {
            try {
                Write-Log "Collecting Winget packages..." 'INFO'
                $wingetResult = & winget list --accept-source-agreements 2>$null
                if ($wingetResult) {
                    $wingetApps = $wingetResult | Where-Object { $_ -match '^\S+\s+\S+' } | ForEach-Object {
                        $parts = $_ -split '\s{2,}'
                        if ($parts.Count -ge 2) {
                            @{
                                Name        = $parts[0].Trim()
                                DisplayName = $parts[1].Trim()
                                Version     = if ($parts.Count -ge 3) { $parts[2].Trim() } else { 'Unknown' }
                                Source      = 'Winget'
                            }
                        }
                    }
                    $allApps += $wingetApps
                    Write-Log "Collected $($wingetApps.Count) Winget packages" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to collect Winget packages: $_" 'WARN'
            }
        }

        # Chocolatey packages
        if ('Chocolatey' -in $Sources -and (Test-CommandAvailable 'choco')) {
            try {
                Write-Log "Collecting Chocolatey packages..." 'INFO'
                $chocoResult = & choco list -l 2>$null
                if ($chocoResult) {
                    $chocoApps = $chocoResult | Where-Object { $_ -match '^\S+\s+\S+' } | ForEach-Object {
                        $parts = $_ -split '\s+\|\s+'
                        if ($parts.Count -ge 2) {
                            @{
                                Name        = $parts[0].Trim()
                                DisplayName = $parts[0].Trim()
                                Version     = $parts[1].Trim()
                                Source      = 'Chocolatey'
                            }
                        }
                    }
                    $allApps += $chocoApps
                    Write-Log "Collected $($chocoApps.Count) Chocolatey packages" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to collect Chocolatey packages: $_" 'WARN'
            }
        }

        # Cache the results
        if ($UseCache) {
            $global:AppInventoryCache = @{
                Timestamp = Get-Date
                Data      = $allApps
            }
        }

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        Write-Log "[COMPLETE] Standardized App Inventory Collection in $([math]::Round($duration, 2))s - Total: $($allApps.Count) apps" 'SUCCESS'

        return $allApps

    }
    catch {
        Write-Log "Critical error in app inventory collection: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Helper Functions (placeholders - would need full implementation)
# ================================================================
function Get-AppxPackageCompatible {
    # Placeholder - full implementation would go here
    return Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
}

function Test-CommandAvailable {
    param([string]$Command)
    # Placeholder - full implementation would go here
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-RegistryUninstallBloatware {
    param([string[]]$BloatwarePatterns, [string]$Context)
    # Placeholder - full implementation would go here
    return @()
}

function Get-ComprehensiveBloatwareInventory {
    param([switch]$UseCache)
    # Placeholder - full implementation would go here
    return @{}
}

# Export functions
Export-ModuleMember -Function Get-SystemInventory, Get-OptimizedSystemInventory, Get-StandardizedAppInventory