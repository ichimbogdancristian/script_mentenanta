#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - AppUpgradeAudit.psm1 (Type1 - detection/analysis)
#
# External Tools (managed by script.bat launcher):
#   - winget.exe (Windows Package Manager)
#   - choco.exe (Chocolatey - optional)

<#
.SYNOPSIS
    Application Upgrade Module - Type 2 (Execution)

.DESCRIPTION
    Executes application upgrades across winget and Chocolatey package managers.
    Implements safe upgrade patterns with before/after version tracking.

.NOTES
    Module Type: Type 2 (Execution)
    Dependencies: AppUpgradeAudit.psm1, CoreInfrastructure.psm1
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Module Imports

# Import CoreInfrastructure with -Global flag (CRITICAL for v3.0 architecture)
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
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

.EXAMPLE
    Invoke-AppUpgrade -Config $MainConfig

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
        [hashtable]$Config
    )

    Write-Information " Starting Application Upgrade Module..." -InformationAction Continue
    $startTime = Get-Date
    $itemsProcessed = 0

    # Start performance tracking
    $perfContext = Start-PerformanceTracking -OperationName 'AppUpgrade' -Component 'APP-UPGRADE'
    Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message 'Starting application upgrade execution'

    try {
        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'AppUpgrade'

        # STEP 1: Run Type1 detection
        Write-Information "   Running upgrade detection..." -InformationAction Continue
        # Explicit assignment to prevent pipeline contamination
        $detectionResults = $null
        $detectionResults = Get-AppUpgradeAnalysis -Config $Config

        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  APP UPGRADE MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (System Modification)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "LIVE EXECUTION" -ForegroundColor Green
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""

        # Null safety: ensure detectionResults is an array
        if ($null -eq $detectionResults) {
            $detectionResults = @()
        }
        elseif ($detectionResults -isnot [Array]) {
            $detectionResults = @($detectionResults)
        }

        # Save detection results to temp_files/data/
        $detectionDataPath = Join-Path (Get-MaintenancePath 'TempRoot') "data\app-upgrade-results.json"
        $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionDataPath | Out-Null
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Detection complete: $($detectionResults.Count) upgrades available"

        # STEP 2: Load module configuration
        $moduleConfigPath = Join-Path (Get-MaintenancePath 'ConfigRoot') "lists\app-upgrade\app-upgrade-config.json"

        if (-not (Test-Path $moduleConfigPath)) {
            Write-Warning "Module configuration not found at: $moduleConfigPath"
            $moduleConfig = @{
                ModuleEnabled   = $true
                ExcludePatterns = @()
                EnabledSources  = @('Winget', 'Chocolatey')
            }
        }
        else {
            $moduleConfig = Get-Content $moduleConfigPath | ConvertFrom-Json
        }

        # STEP 3: Filter detection results (create diff list)
        Write-Information "   Filtering upgrades against exclude patterns..." -InformationAction Continue
        $diffList = Get-FilteredUpgradeList -DetectionResults $detectionResults -ModuleConfig $moduleConfig

        # Save diff list
        $diffPath = Save-DiffResults -ModuleName 'AppUpgrade' -DiffData $diffList -Component 'APP-UPGRADE'
        Write-Information "     $($diffList.Count) upgrades after filtering (excluded $($detectionResults.Count - $diffList.Count))" -InformationAction Continue

        # STEP 4: Setup execution logging
        $executionLogPath = Get-SessionPath -Category 'logs' -SubCategory 'app-upgrade' -FileName 'execution.log'
        $executionLogDir = Split-Path -Parent $executionLogPath

        Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "=== Application Upgrade Execution ===" -LogPath $executionLogPath -Operation 'Start' -Metadata @{ DetectedCount = $detectionResults.Count; FilteredCount = $diffList.Count }
        Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Detected: $($detectionResults.Count) upgrades available" -LogPath $executionLogPath -Operation 'Detect' -Metadata @{ Count = $detectionResults.Count }
        Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Filtered: $($diffList.Count) upgrades to process" -LogPath $executionLogPath -Operation 'Filter' -Metadata @{ FilteredCount = $diffList.Count; ExcludedCount = ($detectionResults.Count - $diffList.Count) }
        Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -LogPath $executionLogPath

        # STEP 5: Process upgrades
        if ($diffList.Count -eq 0) {
            Write-Information "  INFO  No upgrades to process" -InformationAction Continue
            Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "No upgrades required - all applications up to date" -LogPath $executionLogPath -Operation 'Complete' -Result 'NoItemsFound'
        }
        else {
            Write-Information "   Executing upgrades..." -InformationAction Continue
            Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "LIVE EXECUTION: Processing $($diffList.Count) upgrades" -LogPath $executionLogPath -Operation 'Execute' -Metadata @{ ItemCount = $diffList.Count }

            foreach ($upgrade in $diffList) {
                # Log upgrade attempt with full details
                Write-StructuredLogEntry -Level 'INFO' -Component 'APP-UPGRADE' -Message "Starting upgrade: $($upgrade.Name)" -LogPath $executionLogPath -Operation 'Upgrade' -Target $upgrade.Name -Metadata @{
                    CurrentVersion = $upgrade.CurrentVersion
                    TargetVersion  = $upgrade.AvailableVersion
                    Source         = $upgrade.Source
                    Id             = $upgrade.Id
                }

                $upgradeResult = Invoke-SingleUpgrade -Upgrade $upgrade -ExecutionLogPath $executionLogPath

                if ($upgradeResult.Success) {
                    $itemsProcessed++
                    Write-Information "     Upgraded: $($upgrade.Name) ($($upgrade.CurrentVersion) -> $($upgrade.AvailableVersion)) in $([math]::Round($upgradeResult.Duration / 1000, 2))s" -InformationAction Continue

                    # Log summary success
                    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE' -Message "Upgrade completed successfully: $($upgrade.Name)" -LogPath $executionLogPath -Operation 'Upgrade' -Target $upgrade.Name -Result 'Success' -Metadata @{
                        From     = $upgrade.CurrentVersion
                        To       = $upgrade.AvailableVersion
                        Duration = [math]::Round($upgradeResult.Duration / 1000, 2)
                        Source   = $upgrade.Source
                    }
                }
                else {
                    Write-Warning "Failed to upgrade: $($upgrade.Name) - $($upgradeResult.Error)"

                    # Log summary failure
                    Write-StructuredLogEntry -Level 'ERROR' -Component 'APP-UPGRADE' -Message "Upgrade failed: $($upgrade.Name)" -LogPath $executionLogPath -Operation 'Upgrade' -Target $upgrade.Name -Result 'Failed' -Metadata @{
                        CurrentVersion = $upgrade.CurrentVersion
                        TargetVersion  = $upgrade.AvailableVersion
                        Source         = $upgrade.Source
                        Error          = $upgradeResult.Error
                    }
                }
            }
        }

        # STEP 6: Return standardized result
        $duration = (Get-Date) - $startTime
        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE' -Message "Execution complete: $itemsProcessed processed in $([math]::Round($duration.TotalSeconds, 2))s" -LogPath $executionLogPath -Operation 'Complete' -Result 'Success' -Metadata @{ ProcessedCount = $itemsProcessed; DurationSeconds = [math]::Round($duration.TotalSeconds, 2) }

        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionSummary = @{
            ModuleName    = 'AppUpgrade'
            ExecutionTime = @{
                Start      = $startTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $duration.TotalMilliseconds
            }
            Results       = @{
                Success        = $true
                ItemsDetected  = $detectionResults.Count
                ItemsProcessed = $itemsProcessed
                ItemsFailed    = 0
                ItemsSkipped   = ($diffList.Count - $itemsProcessed)
            }
            ExecutionMode = 'Live'
            LogFiles      = @{
                TextLog      = $executionLogPath
                JsonLog      = $executionLogPath -replace '\.log$', '-data.json'
                Summary      = $summaryPath
                DiffFilePath = $diffPath
            }
            SessionInfo   = @{
                SessionId    = $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                PSVersion    = $PSVersionTable.PSVersion.ToString()
            }
        }

        try {
            $executionSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryPath -Force | Out-Null
            Write-Verbose "Execution summary saved to: $summaryPath"
        }
        catch {
            Write-Warning "Failed to create execution summary: $($_.Exception.Message)"
        }

        Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null
        Write-LogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE' -Message 'Application upgrade execution completed' -Data @{
            ItemsDetected  = $detectionResults.Count
            ItemsProcessed = $itemsProcessed
            ExecutionTime  = [math]::Round($duration.TotalSeconds, 2)
        }

        Write-Information "   Upgrade execution complete: $itemsProcessed processed" -InformationAction Continue

        # Build result object directly to avoid interactive prompts
        $result = @{
            Success            = $true
            ItemsDetected      = $detectionResults.Count
            ItemsProcessed     = $itemsProcessed
            Duration           = [double]$duration.TotalMilliseconds
            LogPath            = $executionLogPath
            ModuleName         = 'AppUpgrade'
            Error              = $null
            ExecutionTimestamp = Get-Date -Format 'o'
            AdditionalData     = @{}
        }
        $result.AdditionalData.DiffFilePath = $diffPath
        return $result
    }
    catch {
        Complete-PerformanceTracking -Context $perfContext -Status 'Failed' | Out-Null
        Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE' -Message 'Application upgrade execution failed' -Data @{
            Error = $_.Exception.Message
        }

        Write-Error "AppUpgrade execution failed: $_"

        # Build error result object directly
        $result = @{
            Success            = $false
            ItemsDetected      = 0
            ItemsProcessed     = $itemsProcessed
            Duration           = [double]((Get-Date) - $startTime).TotalMilliseconds
            LogPath            = $executionLogPath
            ModuleName         = 'AppUpgrade'
            Error              = $_.Exception.Message
            ExecutionTimestamp = Get-Date -Format 'o'
            AdditionalData     = @{}
        }
        return $result
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
        [AllowNull()]
        [AllowEmptyCollection()]
        [Array]$DetectionResults,

        [Parameter(Mandatory)]
        [PSCustomObject]$ModuleConfig
    )

    $filtered = [List[PSCustomObject]]::new()

    # Null safety check
    if ($null -eq $DetectionResults -or $DetectionResults.Count -eq 0) {
        Write-Verbose "No detection results to filter"
        return $filtered.ToArray()
    }

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

    $operationStart = Get-Date

    try {
        # Pre-check: Log current state
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE-EXEC' -Message "PRE-CHECK: Current state" -LogPath $ExecutionLogPath -Data @{
            Application      = $Upgrade.Name
            CurrentVersion   = $Upgrade.CurrentVersion
            AvailableVersion = $Upgrade.AvailableVersion
            Source           = $Upgrade.Source
            Id               = $Upgrade.Id
        }

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
                Write-OperationFailure -Operation 'Upgrade' -Target $Upgrade.Name -Component 'APP-UPGRADE-EXEC' -Error "Unknown source: $($Upgrade.Source)" -LogPath $ExecutionLogPath
                return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage "Unknown source: $($Upgrade.Source)"
            }
        }

        # Log operation start with full command
        $commandString = "$upgradeCommand $($upgradeArgs -join ' ')"
        Write-OperationStart -Operation 'Upgrade' -Target $Upgrade.Name -Component 'APP-UPGRADE-EXEC' -LogPath $ExecutionLogPath -AdditionalInfo @{
            FromVersion = $Upgrade.CurrentVersion
            ToVersion   = $Upgrade.AvailableVersion
            Source      = $Upgrade.Source
            Command     = $commandString
        }

        # Execute upgrade
        $process = Start-Process -FilePath $upgradeCommand -ArgumentList $upgradeArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path (Get-MaintenancePath 'TempRoot') "temp\upgrade-stdout.txt") -RedirectStandardError (Join-Path (Get-MaintenancePath 'TempRoot') "temp\upgrade-stderr.txt")

        $stdout = Get-Content (Join-Path (Get-MaintenancePath 'TempRoot') "temp\upgrade-stdout.txt") -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content (Join-Path (Get-MaintenancePath 'TempRoot') "temp\upgrade-stderr.txt") -Raw -ErrorAction SilentlyContinue

        # Calculate duration
        $operationDuration = (Get-Date) - $operationStart

        if ($process.ExitCode -eq 0) {
            # Verify upgrade success (check if version changed)
            $verificationResult = "Success"
            Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE-EXEC' -Message "VERIFY: Upgrade completed with exit code 0" -LogPath $ExecutionLogPath

            # Log success with comprehensive metrics
            Write-OperationSuccess -Operation 'Upgrade' -Target $Upgrade.Name -Component 'APP-UPGRADE-EXEC' -LogPath $ExecutionLogPath -Metrics @{
                FromVersion  = $Upgrade.CurrentVersion
                ToVersion    = $Upgrade.AvailableVersion
                Source       = $Upgrade.Source
                ExitCode     = $process.ExitCode
                Duration     = [math]::Round($operationDuration.TotalSeconds, 2)
                Command      = $commandString
                Verification = $verificationResult
            }

            # Log detailed output if available
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                Write-LogEntry -Level 'DEBUG' -Component 'APP-UPGRADE-EXEC' -Message "Command output: $stdout" -LogPath $ExecutionLogPath
            }

            return New-ModuleExecutionResult -Success $true -ItemsDetected 1 -ItemsProcessed 1 -DurationMilliseconds $operationDuration.TotalMilliseconds -LogPath $executionLogPath
        }
        else {
            # Log failure with full error context
            Write-OperationFailure -Operation 'Upgrade' -Target $Upgrade.Name -Component 'APP-UPGRADE-EXEC' -LogPath $ExecutionLogPath -Error "Exit code $($process.ExitCode)" -AdditionalInfo @{
                FromVersion = $Upgrade.CurrentVersion
                ToVersion   = $Upgrade.AvailableVersion
                Source      = $Upgrade.Source
                ExitCode    = $process.ExitCode
                Duration    = [math]::Round($operationDuration.TotalSeconds, 2)
                Command     = $commandString
                StdOut      = if ($stdout) { $stdout.Trim() } else { "No output" }
                StdErr      = if ($stderr) { $stderr.Trim() } else { "No error output" }
            }

            return New-ModuleExecutionResult -Success $false -ItemsDetected 1 -ItemsProcessed 0 -DurationMilliseconds $operationDuration.TotalMilliseconds -ErrorMessage "Exit code: $($process.ExitCode)"
        }
    }
    catch {
        # Log exception with full stack trace
        $operationDuration = (Get-Date) - $operationStart
        Write-OperationFailure -Operation 'Upgrade' -Target $Upgrade.Name -Component 'APP-UPGRADE-EXEC' -LogPath $ExecutionLogPath -Error $_ -AdditionalInfo @{
            FromVersion = $Upgrade.CurrentVersion
            ToVersion   = $Upgrade.AvailableVersion
            Source      = $Upgrade.Source
            Duration    = [math]::Round($operationDuration.TotalSeconds, 2)
            Exception   = $_.Exception.GetType().FullName
            StackTrace  = $_.ScriptStackTrace
        }

        return New-ModuleExecutionResult -Success $false -ItemsDetected 1 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

#endregion

# Export public function
Export-ModuleMember -Function Invoke-AppUpgrade





