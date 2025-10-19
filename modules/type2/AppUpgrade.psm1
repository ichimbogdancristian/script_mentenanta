#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (for logging and configuration)
#   - AppUpgradeAudit.psm1 (Type 1 module for detection)

<#
.SYNOPSIS
    Application Upgrade Module - Type 2 (Execution)

.DESCRIPTION
    Executes application upgrades across winget and Chocolatey package managers.
    Implements safe upgrade patterns with before/after version tracking.

.NOTES
    Module Type: Type 2 (Execution)
    Dependencies: winget, chocolatey (optional), CoreInfrastructure, AppUpgradeAudit
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Module Imports

# Import CoreInfrastructure with -Global flag (CRITICAL for v3.0 architecture)
$CoreInfraPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'modules\core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Import Type1 module (self-contained pattern)
$Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\AppUpgradeAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force -WarningAction SilentlyContinue
}
else {
    Write-Warning "AppUpgradeAudit module not found at: $Type1ModulePath"
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Executes application upgrades based on audit results

.DESCRIPTION
    Main execution function for AppUpgrade module. Calls Type1 detection,
    analyzes upgradeable packages, filters against exclude patterns,
    and executes upgrades with comprehensive logging.

.PARAMETER Config
    Configuration hashtable from main-config.json

.PARAMETER DryRun
    If specified, simulates upgrade actions without making actual changes

.EXAMPLE
    Invoke-AppUpgrade -Config $MainConfig

.EXAMPLE
    Invoke-AppUpgrade -Config $MainConfig -DryRun

.OUTPUTS
    Hashtable with execution results:
    @{
        Success = $true/$false
        ItemsDetected = 15
        ItemsProcessed = 12
        Duration = 45000 (milliseconds)
    }
#>
function Invoke-AppUpgrade {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter()]
        [switch]$DryRun
    )

    Write-Information "🔄 Starting Application Upgrade Module..." -InformationAction Continue
    $startTime = Get-Date
    $itemsProcessed = 0

    # Start performance tracking
    $perfContext = Start-PerformanceTracking -OperationName 'AppUpgrade' -Component 'APP-UPGRADE'
    Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message 'Starting application upgrade execution'

    try {
        # STEP 1: Run Type1 detection
        Write-Information "  🔍 Running upgrade detection..." -InformationAction Continue
        $detectionResults = Get-AppUpgradeAnalysis -Config $Config
        
        # Save detection results to temp_files/data/
        $detectionDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\app-upgrade-results.json"
        $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionDataPath
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Detection complete: $($detectionResults.Count) upgrades available"

        # STEP 2: Load module configuration
        $moduleConfigPath = Join-Path $Global:ProjectPaths.Config "app-upgrade-config.json"
        if (-not (Test-Path $moduleConfigPath)) {
            Write-Warning "Module configuration not found at: $moduleConfigPath"
            $moduleConfig = @{
                ModuleEnabled    = $true
                ExcludePatterns  = @()
                EnabledSources   = @('Winget', 'Chocolatey')
            }
        }
        else {
            $moduleConfig = Get-Content $moduleConfigPath | ConvertFrom-Json
        }

        # STEP 3: Filter detection results (create diff list)
        Write-Information "  📋 Filtering upgrades against exclude patterns..." -InformationAction Continue
        $diffList = Get-FilteredUpgradeList -DetectionResults $detectionResults -ModuleConfig $moduleConfig
        
        # Save diff list
        $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\app-upgrade-diff.json"
        $diffList | ConvertTo-Json -Depth 10 | Set-Content $diffPath
        Write-Information "    ✓ $($diffList.Count) upgrades after filtering (excluded $($detectionResults.Count - $diffList.Count))" -InformationAction Continue

        # STEP 4: Setup execution logging
        $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\app-upgrade"
        New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "=== Application Upgrade Execution ===" -LogPath $executionLogPath
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Detected: $($detectionResults.Count) upgrades available" -LogPath $executionLogPath
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Filtered: $($diffList.Count) upgrades to process" -LogPath $executionLogPath
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "DryRun: $DryRun" -LogPath $executionLogPath
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -LogPath $executionLogPath

        # STEP 5: Process upgrades (with DryRun check)
        if ($diffList.Count -eq 0) {
            Write-Information "  ℹ️  No upgrades to process" -InformationAction Continue
            Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "No upgrades required - all applications up to date" -LogPath $executionLogPath
        }
        elseif ($DryRun) {
            Write-Information "  🧪 DRY-RUN MODE: Simulating upgrades..." -InformationAction Continue
            foreach ($upgrade in $diffList) {
                Write-Information "    [DRY-RUN] Would upgrade: $($upgrade.Name) ($($upgrade.CurrentVersion) → $($upgrade.AvailableVersion))" -InformationAction Continue
                Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "DRY-RUN: Would upgrade $($upgrade.Name) from $($upgrade.CurrentVersion) to $($upgrade.AvailableVersion) via $($upgrade.Source)" -LogPath $executionLogPath
                $itemsProcessed++
            }
        }
        else {
            Write-Information "  🚀 Executing upgrades..." -InformationAction Continue
            foreach ($upgrade in $diffList) {
                $upgradeResult = Invoke-SingleUpgrade -Upgrade $upgrade -ExecutionLogPath $executionLogPath
                if ($upgradeResult.Success) {
                    $itemsProcessed++
                    Write-Information "    ✅ Upgraded: $($upgrade.Name) ($($upgrade.CurrentVersion) → $($upgrade.AvailableVersion))" -InformationAction Continue
                }
                else {
                    Write-Warning "Failed to upgrade: $($upgrade.Name) - $($upgradeResult.Error)"
                }
            }
        }

        # STEP 6: Return standardized result
        $duration = (Get-Date) - $startTime
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Execution complete: $itemsProcessed processed in $([math]::Round($duration.TotalSeconds, 2))s" -LogPath $executionLogPath

        Complete-PerformanceTracking -Context $perfContext -Status 'Success'
        Write-LogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE' -Message 'Application upgrade execution completed' -Data @{
            ItemsDetected  = $detectionResults.Count
            ItemsProcessed = $itemsProcessed
            ExecutionTime  = [math]::Round($duration.TotalSeconds, 2)
        }

        Write-Information "  ✅ Upgrade execution complete: $itemsProcessed processed" -InformationAction Continue

        return @{
            Success        = $true
            ItemsDetected  = $detectionResults.Count
            ItemsProcessed = $itemsProcessed
            Duration       = $duration.TotalMilliseconds
        }
    }
    catch {
        Complete-PerformanceTracking -Context $perfContext -Status 'Failed'
        Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE' -Message 'Application upgrade execution failed' -Data @{
            Error = $_.Exception.Message
        }

        Write-Error "AppUpgrade execution failed: $_"
        return @{
            Success        = $false
            ItemsDetected  = 0
            ItemsProcessed = $itemsProcessed
            Duration       = ((Get-Date) - $startTime).TotalMilliseconds
        }
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Filters upgrade list against exclude patterns
#>
function Get-FilteredUpgradeList {
    [CmdletBinding()]
    [OutputType([Array])]
    param(
        [Parameter(Mandatory)]
        [Array]$DetectionResults,

        [Parameter(Mandatory)]
        [PSCustomObject]$ModuleConfig
    )

    $filtered = [List[PSCustomObject]]::new()

    foreach ($upgrade in $DetectionResults) {
        # Check if source is enabled
        if ($ModuleConfig.EnabledSources -notcontains $upgrade.Source) {
            Write-Verbose "Skipping $($upgrade.Name) - source $($upgrade.Source) not enabled"
            continue
        }

        # Check against exclude patterns
        $excluded = $false
        foreach ($pattern in $ModuleConfig.ExcludePatterns) {
            if ($upgrade.Name -like $pattern) {
                Write-Verbose "Excluding $($upgrade.Name) - matches pattern: $pattern"
                $excluded = $true
                break
            }
        }

        if (-not $excluded) {
            $filtered.Add($upgrade)
        }
    }

    return [Array]$filtered
}

<#
.SYNOPSIS
    Executes a single application upgrade
#>
function Invoke-SingleUpgrade {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Upgrade,

        [Parameter(Mandatory)]
        [string]$ExecutionLogPath
    )

    $startTime = Get-Date

    try {
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE-EXEC' -Message "Processing upgrade: $($Upgrade.Name) ($($Upgrade.CurrentVersion) → $($Upgrade.AvailableVersion))" -LogPath $ExecutionLogPath

        $upgradeCommand = $null
        $upgradeArgs = @()

        # Build upgrade command based on source
        switch ($Upgrade.Source) {
            'Winget' {
                $upgradeCommand = 'winget'
                $upgradeArgs = @(
                    'upgrade',
                    '--id', $Upgrade.Id,
                    '--silent',
                    '--accept-package-agreements',
                    '--accept-source-agreements',
                    '--disable-interactivity'
                )
            }
            'Chocolatey' {
                $upgradeCommand = 'choco'
                $upgradeArgs = @(
                    'upgrade', $Upgrade.Name,
                    '-y',
                    '--limit-output',
                    '--no-progress'
                )
            }
            default {
                Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE-EXEC' -Message "Unknown source: $($Upgrade.Source)" -LogPath $ExecutionLogPath
                return @{ Success = $false; Error = "Unknown source: $($Upgrade.Source)" }
            }
        }

        # Execute upgrade
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE-EXEC' -Message "Executing: $upgradeCommand $($upgradeArgs -join ' ')" -LogPath $ExecutionLogPath
        
        $process = Start-Process -FilePath $upgradeCommand -ArgumentList $upgradeArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Global:ProjectPaths.TempFiles "temp\upgrade-stdout.txt") -RedirectStandardError (Join-Path $Global:ProjectPaths.TempFiles "temp\upgrade-stderr.txt")
        
        $stdout = Get-Content (Join-Path $Global:ProjectPaths.TempFiles "temp\upgrade-stdout.txt") -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content (Join-Path $Global:ProjectPaths.TempFiles "temp\upgrade-stderr.txt") -Raw -ErrorAction SilentlyContinue

        if ($process.ExitCode -eq 0) {
            $duration = (Get-Date) - $startTime
            Write-LogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE-EXEC' -Message "Upgrade successful: $($Upgrade.Name) completed in $([math]::Round($duration.TotalSeconds, 2))s" -LogPath $ExecutionLogPath
            
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                Write-LogEntry -Level 'DEBUG' -Component 'APP-UPGRADE-EXEC' -Message "Output: $stdout" -LogPath $ExecutionLogPath
            }

            return @{ Success = $true; Duration = $duration.TotalMilliseconds }
        }
        else {
            Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE-EXEC' -Message "Upgrade failed: Exit code $($process.ExitCode)" -LogPath $ExecutionLogPath
            
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE-EXEC' -Message "Error output: $stderr" -LogPath $ExecutionLogPath
            }

            return @{ Success = $false; Error = "Exit code: $($process.ExitCode)" }
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE-EXEC' -Message "Exception during upgrade: $($_.Exception.Message)" -LogPath $ExecutionLogPath
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

#endregion

# Export public function
Export-ModuleMember -Function Invoke-AppUpgrade
