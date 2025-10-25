#Requires -Version 7.0

<#
.SYNOPSIS
    User Interface Module - Interactive Menus and User Input

.DESCRIPTION
    Provides countdown-based interactive menus with automatic fallback to default options.
    Supports unattended execution, dry-run modes, and task selection capabilities.
    Consolidated from MenuSystem module focusing on user interaction.

.NOTES
    Module Type: Core Infrastructure (Consolidated)
    Dependencies: CoreInfrastructure for logging
    Author: Windows Maintenance Automation Project
    Version: 2.0.0 (Consolidated)
#>

using namespace System.Collections.Generic

# Import CoreInfrastructure for logging
$CoreInfraPath = Join-Path $PSScriptRoot 'CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}

#region Public Functions

<#
.SYNOPSIS
    Shows the main execution menu with hierarchical countdown system

.DESCRIPTION
    Displays a hierarchical menu system with 20-second countdowns:
    - Main menu: Choose between normal execution or dry-run
    - Sub-menus: Choose between all tasks or specific task numbers
    Auto-selects defaults when countdown expires.

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer (default: 20)

.PARAMETER AvailableTasks
    Array of available tasks to display and select from

.OUTPUTS
    [hashtable] Returns execution parameters: DryRun, SelectedTasks

.EXAMPLE
    $result = Show-MainMenu -AvailableTasks $taskList
    # Returns: @{ DryRun = $false; SelectedTasks = @(1,2,3,4,5) }
#>
function Show-MainMenu {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$CountdownSeconds = 20,

        [Parameter()]
        [array]$AvailableTasks = @()
    )
    
    # Start performance tracking for menu display
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'MainMenuDisplay' -Component 'USER-INTERFACE'
        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message 'Displaying hierarchical menu system' -Data @{ CountdownSeconds = $CountdownSeconds; TaskCount = $AvailableTasks.Count }
    }
    catch {
        # CoreInfrastructure not available, continue with standard logging
        Write-Host "Note: Extended logging unavailable for this session" -ForegroundColor Gray
    }

    # Initialize result object
    $result = @{
        DryRun        = $false
        SelectedTasks = @()
    }

    # ===== MAIN MENU =====
    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "    Windows Maintenance Automation v2.1.1" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select execution mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Execute normally (recommended)" -ForegroundColor Green
    Write-Host "  [2] Dry-run mode (simulate changes)" -ForegroundColor Cyan
    Write-Host ""

    # Show available tasks if provided
    if ($AvailableTasks.Count -gt 0) {
        Write-Host "Available maintenance tasks:" -ForegroundColor Gray
        for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
            $task = $AvailableTasks[$i]
            if ($task -is [hashtable] -and $task.ContainsKey('Name') -and $task.ContainsKey('Description')) {
                $taskName = $task.Name
                $taskDesc = $task.Description
                Write-Host "    [$($i+1)] $taskName" -ForegroundColor DarkGray
                Write-Host "        $taskDesc" -ForegroundColor DarkGray
            }
            elseif ($task -is [hashtable] -and $task.ContainsKey('Name')) {
                Write-Host "    [$($i+1)] $($task.Name)" -ForegroundColor DarkGray
            }
            elseif ($task -is [hashtable]) {
                # If it's a hashtable but doesn't have expected properties, show as string
                Write-Host "    [$($i+1)] Maintenance Task $($i+1)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "    [$($i+1)] $($task)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    $mainSelection = Start-CountdownMenu -CountdownSeconds $CountdownSeconds -DefaultOption 1 -ValidOptions @(1, 2)

    # Set dry-run mode based on main selection
    $result.DryRun = ($mainSelection -eq 2)

    # ===== SUB-MENU =====
    Write-Host ""
    $modeText = if ($result.DryRun) { "DRY-RUN" } else { "NORMAL" }
    Write-Host "Selected: $modeText execution mode" -ForegroundColor $(if ($result.DryRun) { 'Cyan' } else { 'Green' })
    Write-Host ""
    Write-Host "Select task execution:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Execute all tasks (recommended)" -ForegroundColor Green
    Write-Host "  [2] Execute specific task numbers" -ForegroundColor Magenta
    Write-Host ""

    $subSelection = Start-CountdownMenu -CountdownSeconds $CountdownSeconds -DefaultOption 1 -ValidOptions @(1, 2)

    # Handle task selection based on sub-menu choice
    if ($subSelection -eq 1) {
        # All tasks selected
        $result.SelectedTasks = 1..$AvailableTasks.Count
        Write-Host ""
        Write-Host "Selected: All $($AvailableTasks.Count) tasks" -ForegroundColor Green
    }
    else {
        # Specific task selection
        Write-Host ""
        Write-Host "Enter task numbers (comma-separated, e.g., 1,3,5):" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
            if ($AvailableTasks[$i] -is [hashtable]) {
                $taskName = $AvailableTasks[$i].Name
                $taskDesc = $AvailableTasks[$i].Description
                Write-Host "  [$($i+1)] $taskName" -ForegroundColor Green
                Write-Host "      $taskDesc" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  [$($i+1)] $($AvailableTasks[$i])" -ForegroundColor Green
            }
        }
        Write-Host ""

        $defaultTaskList = "1"
        $taskInput = Start-CountdownInput -CountdownSeconds $CountdownSeconds -DefaultValue $defaultTaskList

        # Parse task numbers
        $result.SelectedTasks = ConvertFrom-TaskNumbers -TaskInput $taskInput -MaxTasks $AvailableTasks.Count

        if ($result.SelectedTasks.Count -eq 0) {
            Write-Host "No valid tasks selected, defaulting to all tasks" -ForegroundColor Yellow
            $result.SelectedTasks = 1..$AvailableTasks.Count
        }
        else {
            Write-Host ""
            Write-Host "Selected tasks: $($result.SelectedTasks -join ', ')" -ForegroundColor Green
        }
    }

    # Complete performance tracking
    try {
        Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $result.SelectedTasks.Count
        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message 'Menu selection completed' -Data @{
            DryRun            = $result.DryRun
            SelectedTaskCount = $result.SelectedTasks.Count
            SelectedTasks     = ($result.SelectedTasks -join ',')
        }
    }
    catch {
        # Logging or performance tracking may not be available
        Write-Verbose "Performance tracking completion failed - continuing"
    }

    return $result
}



<#
.SYNOPSIS
    Shows a confirmation dialog

.DESCRIPTION
    Displays a confirmation prompt with countdown timer and default response.

.PARAMETER Message
    The confirmation message to display

.PARAMETER DefaultResponse
    Default response (Y/N) when countdown expires

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer

.EXAMPLE
    $confirmed = Show-ConfirmationDialog -Message "Proceed with maintenance?" -DefaultResponse "Y"
#>
function Show-ConfirmationDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Y', 'N')]
        [string]$DefaultResponse = 'Y',

        [Parameter()]
        [int]$CountdownSeconds = 15
    )

    Write-Host "`n$Message" -ForegroundColor Yellow
    Write-Host "[$DefaultResponse] will be selected automatically in $CountdownSeconds seconds" -ForegroundColor Gray
    Write-Host ""

    $response = Start-CountdownInput -CountdownSeconds $CountdownSeconds -DefaultValue $DefaultResponse

    return ($response -eq 'Y' -or $response -eq 'y' -or $response -eq $DefaultResponse)
}

<#
.SYNOPSIS
    Displays progress information

.DESCRIPTION
    Shows formatted progress information with optional progress bar.

.PARAMETER Activity
    The activity being performed

.PARAMETER Status
    Current status message

.PARAMETER PercentComplete
    Percentage complete (0-100)

.PARAMETER ShowProgressBar
    Whether to show a visual progress bar

.EXAMPLE
    Show-Progress -Activity "Installing updates" -Status "Update 3 of 10" -PercentComplete 30
#>
function Show-Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,

        [Parameter()]
        [string]$Status = "",

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$PercentComplete = 0,

        [Parameter()]
        [switch]$ShowProgressBar
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    
    if ($ShowProgressBar -and $PercentComplete -gt 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    }
    
    Write-Host "[$timestamp] $Activity" -ForegroundColor Cyan -NoNewline
    if ($Status) {
        Write-Host " - $Status" -ForegroundColor White -NoNewline
    }
    if ($PercentComplete -gt 0) {
        Write-Host " ($PercentComplete%)" -ForegroundColor Gray
    }
    else {
        Write-Host ""
    }
}

<#
.SYNOPSIS
    Displays a summary of results

.DESCRIPTION
    Shows a formatted summary of operation results with color coding.

.PARAMETER Title
    Title of the summary

.PARAMETER Results
    Hashtable of results to display

.PARAMETER ShowDetails
    Whether to show detailed information

.EXAMPLE
    Show-ResultSummary -Title "Maintenance Complete" -Results @{Success=5; Failed=1; Skipped=2}
#>
function Show-ResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [hashtable]$Results
    )

    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "    $Title" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($key in $Results.Keys) {
        $value = $Results[$key]
        $color = switch ($key.ToLower()) {
            'success' { 'Green' }
            'completed' { 'Green' }
            'installed' { 'Green' }
            'failed' { 'Red' }
            'error' { 'Red' }
            'errors' { 'Red' }
            'skipped' { 'Yellow' }
            'warning' { 'Yellow' }
            'warnings' { 'Yellow' }
            default { 'White' }
        }
        
        Write-Host "  $key`: " -ForegroundColor Gray -NoNewline
        Write-Host "$value" -ForegroundColor $color
    }

    Write-Host ""
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Starts a countdown menu with user input
#>
function Start-CountdownMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [int]$DefaultOption,

        [Parameter(Mandatory)]
        [array]$ValidOptions
    )

    $timeLeft = $CountdownSeconds
    $selection = $null

    Write-Host "Auto-selecting option [$DefaultOption] in " -ForegroundColor Gray -NoNewline

    while ($timeLeft -gt 0 -and $null -eq $selection) {
        Write-Host "$timeLeft" -ForegroundColor Yellow -NoNewline
        Write-Host "... " -ForegroundColor Gray -NoNewline

        # Check for user input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $userInput = $key.KeyChar.ToString()
            
            if ($userInput -match '^\d$') {
                $inputNum = [int]$userInput
                if ($inputNum -in $ValidOptions) {
                    $selection = $inputNum
                    Write-Host "`nSelected: $selection" -ForegroundColor Green
                    break
                }
            }
        }

        Start-Sleep -Seconds 1
        $timeLeft--
        Write-Host "`b`b`b`b`b    `b`b`b`b`b" -NoNewline  # Clear the previous number
    }

    if ($null -eq $selection) {
        $selection = $DefaultOption
        Write-Host "`nAuto-selected: $selection" -ForegroundColor Cyan
    }

    return $selection
}

<#
.SYNOPSIS
    Starts a countdown input with default value
#>
function Start-CountdownInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [string]$DefaultValue
    )

    $timeLeft = $CountdownSeconds
    $userInput = ""

    Write-Host "Auto-selecting '$DefaultValue' in " -ForegroundColor Gray -NoNewline

    while ($timeLeft -gt 0) {
        Write-Host "$timeLeft" -ForegroundColor Yellow -NoNewline
        Write-Host "... " -ForegroundColor Gray -NoNewline

        # Check for user input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            
            if ($key.Key -eq 'Enter') {
                if ([string]::IsNullOrWhiteSpace($userInput)) {
                    $userInput = $DefaultValue
                }
                Write-Host "`nSelected: $userInput" -ForegroundColor Green
                return $userInput
            }
            elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                $userInput = $userInput.Substring(0, $userInput.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            elseif ($key.KeyChar -match '[a-zA-Z0-9,\s]') {
                $userInput += $key.KeyChar
                Write-Host $key.KeyChar -NoNewline -ForegroundColor White
            }
        }

        Start-Sleep -Milliseconds 500
        $timeLeft--
        
        # Clear countdown display
        $backspaces = "`b" * ($timeLeft.ToString().Length + 4)
        $spaces = " " * ($timeLeft.ToString().Length + 4)
        Write-Host "$backspaces$spaces$backspaces" -NoNewline
    }

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = $DefaultValue
        Write-Host "`nAuto-selected: $userInput" -ForegroundColor Cyan
    }

    return $userInput
}

<#
.SYNOPSIS
    Converts comma-separated task numbers into an array
#>
function ConvertFrom-TaskNumbers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskInput,

        [Parameter(Mandatory)]
        [int]$MaxTasks
    )

    $selectedTasks = @()
    
    if ([string]::IsNullOrWhiteSpace($TaskInput)) {
        return $selectedTasks
    }

    # Parse comma-separated task numbers
    $taskNumbers = $TaskInput -split ',' | ForEach-Object { $_.Trim() }
    
    foreach ($num in $taskNumbers) {
        if ($num -match '^\d+$') {
            $taskIndex = [int]$num
            if ($taskIndex -ge 1 -and $taskIndex -le $MaxTasks) {
                $selectedTasks += $taskIndex
            }
            else {
                Write-Host "Warning: Task number $taskIndex is out of range (1-$MaxTasks)" -ForegroundColor Yellow
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($num)) {
            Write-Host "Warning: Invalid task number '$num' (must be numeric)" -ForegroundColor Yellow
        }
    }

    return ($selectedTasks | Sort-Object | Get-Unique)
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Show-MainMenu',
    'Show-ConfirmationDialog',
    'Show-Progress',
    'Show-ResultSummary'
)