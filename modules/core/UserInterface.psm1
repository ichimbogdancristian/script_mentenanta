#Requires -Version 7.0

<#
.SYNOPSIS
    User Interface Module v3.0 - Interactive Execution Control

.DESCRIPTION
    Provides countdown-based interactive menus with automatic fallback to default options.
    Manages user input collection, task selection, progress tracking, and result presentation.
    Supports unattended execution and comprehensive user feedback.
    Consolidated from MenuSystem module focusing on user interaction in v3.0 refactoring.

.MODULE ARCHITECTURE
    Purpose:
        Serve as the user-facing interaction layer for the maintenance automation system.
        Provides interactive menu flows when user attendance is available, with graceful
        fallback to automated defaults in unattended scenarios (CI/CD, scheduled tasks).

    Dependencies:
        • CoreInfrastructure.psm1 - For logging (Write-LogEntry)

    Exports:
        • Show-MainMenu - Entry point for interactive execution menu
        • Show-ConfirmationDialog - Prompt user for yes/no decisions
        • Show-Progress - Real-time progress display with task tracking
        • Show-ResultSummary - Display final results and statistics
        • ConvertFrom-TaskNumbers - Parse user input into task number array
        • Show-ProgressBar - Visual progress indicator

    Import Pattern:
        Import-Module UserInterface.psm1 -Force
        # Functions available for use in MaintenanceOrchestrator context

    Used By:
        - MaintenanceOrchestrator.ps1 (primary consumer)
        - No other modules depend on this

.EXECUTION FLOW
    1. MaintenanceOrchestrator detects execution context (interactive vs. unattended)
    2. If interactive: Calls Show-MainMenu to prompt user for execution mode and task selection
    3. If unattended: Uses default parameters (all tasks, normal run mode)
    4. During execution: Calls Show-Progress to update user on completion status
    5. After execution: Calls Show-ResultSummary to display final statistics
    6. User can interrupt with Ctrl+C at menu prompts; confirmed selections proceed

.DATA ORGANIZATION
    Input:
        • User selections from countdown-based prompts
        • Available task list passed from MaintenanceOrchestrator

    Output:
        • Hashtable with execution parameters: @{ SelectedTasks = array }
        • Progress updates written to console with Write-LogEntry calls
        • Final summary table with module results

    Session State:
        • Uses CoreInfrastructure logging for all output
        • No permanent data storage (UI-only module)

.NOTES
    Module Type: Core Infrastructure - User Interface Layer (v3.0)
    Architecture: v3.0 - Split with Consolidated Core
    Line Count: 517 lines
    Version: 3.0.0 (Refactored - Interactive Control)

    Key Design Patterns:
    - Countdown timers: 20 seconds default (configurable) for unattended scenarios
    - Graceful degradation: Falls back to defaults when no user response
    - Comprehensive logging: All user interactions logged for audit trail
    - Cross-platform compatible: Works on Windows, Linux, macOS
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
    - Main menu: Choose between all tasks or specific task numbers
    Auto-selects defaults when countdown expires.

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer (default: 20)

.PARAMETER AvailableTasks
    Array of available tasks to display and select from

.OUTPUTS
    [hashtable] Returns execution parameters: SelectedTasks

.EXAMPLE
    $result = Show-MainMenu -AvailableTasks $taskList
    # Returns: @{ SelectedTasks = @(1,2,3,4,5) }
#>
function Show-MainMenu {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
        SelectedTasks = @()
    }

    # ===== MAIN MENU ===== Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "    Windows Maintenance Automation v3.0.0" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select task execution:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Execute all tasks (recommended)" -ForegroundColor Green
    Write-Host "  [2] Execute specific task numbers" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Tip: Press ENTER for default, ESC to abort" -ForegroundColor DarkGray
    Write-Host ""

    # Show available tasks if provided
    if ($AvailableTasks.Count -gt 0) {
        Write-Host "Available maintenance tasks:" -ForegroundColor White
        Write-Host ""
        for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
            $task = $AvailableTasks[$i]
            $taskNumber = "[$($i+1)]"

            if ($task -is [hashtable] -and $task.ContainsKey('Name') -and $task.ContainsKey('Description')) {
                $taskName = $task.Name
                $taskDesc = $task.Description
                Write-Host "  $taskNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "$taskName" -ForegroundColor White
                Write-Host "      - $taskDesc" -ForegroundColor DarkGray
            }
            elseif ($task -is [hashtable] -and $task.ContainsKey('Name')) {
                Write-Host "  $taskNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "$($task.Name)" -ForegroundColor White
            }
            elseif ($task -is [hashtable]) {
                # If it's a hashtable but doesn't have expected properties, show as string
                Write-Host "  $taskNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "Maintenance Task $($i+1)" -ForegroundColor White
            }
            else {
                Write-Host "  $taskNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "$($task)" -ForegroundColor White
            }
        }
        Write-Host ""
    }

    $mainSelection = Start-CountdownMenu -CountdownSeconds $CountdownSeconds -DefaultOption 1 -ValidOptions @(1, 2)

    # Handle task selection based on main menu choice
    if ($mainSelection -eq 1) {
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
    [OutputType([hashtable])]
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
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,

        [Parameter()]
        [string]$Status = "",

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$PercentComplete = 0,

        [Parameter()]
        [switch]$ShowProgressBar,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Severity = 'Info'
    )

    try {
        $timestamp = Get-Date -Format "HH:mm:ss"

        # Determine color based on severity
        $activityColor = switch ($Severity) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error' { 'Red' }
            default { 'Cyan' }
        }

        if ($ShowProgressBar -and $PercentComplete -gt 0) {
            Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
        }

        Write-Host "[$timestamp] " -ForegroundColor DarkGray -NoNewline
        Write-Host $Activity -ForegroundColor $activityColor -NoNewline

        if ($Status) {
            Write-Host " > " -ForegroundColor DarkGray -NoNewline
            Write-Host $Status -ForegroundColor White -NoNewline
        }

        if ($PercentComplete -gt 0) {
            $progressBar = Show-ProgressBar -Percent $PercentComplete -Width 20 -ShowPercentage:$false
            Write-Host " $progressBar" -NoNewline
            Write-Host " $PercentComplete%" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }

        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message "Progress update" -Data @{
            Activity        = $Activity
            Status          = $Status
            PercentComplete = $PercentComplete
            Severity        = $Severity
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error in Show-Progress: $_"
        # Fallback to simple output
        Write-Host "$Activity - $Status" -ForegroundColor White
    }
}

<#
.SYNOPSIS
    Displays a visual progress bar

.DESCRIPTION
    Renders a text-based progress bar with customizable appearance.

.PARAMETER Percent
    Percentage complete (0-100)

.PARAMETER Width
    Width of the progress bar in characters

.PARAMETER ShowPercentage
    Whether to show percentage text with the bar

.PARAMETER Completed
    Character to use for completed portion (default: '#')

.PARAMETER Remaining
    Character to use for remaining portion (default: '-')

.OUTPUTS
    [string] Visual progress bar string

.EXAMPLE
    Show-ProgressBar -Percent 75 -Width 30
    # Returns: "[######################--------] 75%"

.NOTES
    Used internally by Show-Progress and can be called independently for custom displays
#>
function Show-ProgressBar {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Percent,

        [Parameter()]
        [ValidateRange(10, 100)]
        [int]$Width = 30,

        [Parameter()]
        [switch]$ShowPercentage,

        [Parameter()]
        [string]$Completed = '#',

        [Parameter()]
        [string]$Remaining = '-'
    )

    try {
        $completedWidth = [math]::Floor($Width * ($Percent / 100))
        $remainingWidth = $Width - $completedWidth

        $completedBar = $Completed * $completedWidth
        $remainingBar = $Remaining * $remainingWidth

        $progressBar = "[$completedBar$remainingBar]"

        if ($ShowPercentage) {
            $progressBar += " $Percent%"
        }

        return $progressBar
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error creating progress bar: $_"
        return "[Progress: $Percent%]"
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
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Results,

        [Parameter()]
        [timespan]$Duration
    )

    try {
        Write-Host "`n===================================================" -ForegroundColor Cyan
        Write-Host "  $Title" -ForegroundColor White
        Write-Host "===================================================" -ForegroundColor Cyan
        Write-Host ""

        # Calculate maximum key length for alignment
        $maxKeyLength = ($Results.Keys | Measure-Object -Property Length -Maximum).Maximum
        $maxKeyLength = [math]::Max($maxKeyLength, 15)

        # Calculate total if numeric values present
        $total = 0
        $hasNumericValues = $false

        foreach ($key in $Results.Keys | Sort-Object) {
            $value = $Results[$key]

            # Determine color based on key
            $color = switch ($key.ToLower()) {
                'success' { 'Green' }
                'successful' { 'Green' }
                'completed' { 'Green' }
                'installed' { 'Green' }
                'processed' { 'Green' }
                'failed' { 'Red' }
                'error' { 'Red' }
                'errors' { 'Red' }
                'skipped' { 'Yellow' }
                'warning' { 'Yellow' }
                'warnings' { 'Yellow' }
                'detected' { 'Cyan' }
                'total' { 'White' }
                default { 'Gray' }
            }

            # Format key with padding
            $paddedKey = $key.PadRight($maxKeyLength)

            Write-Host "  $paddedKey : " -ForegroundColor DarkGray -NoNewline
            Write-Host "$value" -ForegroundColor $color

            # Sum numeric values for total (exclude 'total' key itself)
            if ($value -is [int] -and $key.ToLower() -ne 'total') {
                $total += $value
                $hasNumericValues = $true
            }
        }

        # Show total if not already present
        if ($hasNumericValues -and -not $Results.ContainsKey('Total')) {
            Write-Host ""
            $paddedTotal = 'Total'.PadRight($maxKeyLength)
            Write-Host "  $paddedTotal : " -ForegroundColor White -NoNewline
            Write-Host "$total" -ForegroundColor White
        }

        # Show duration if provided
        if ($Duration) {
            Write-Host ""
            $paddedDuration = 'Duration'.PadRight($maxKeyLength)
            $durationStr = if ($Duration.TotalMinutes -ge 1) {
                "{0:N1} minutes" -f $Duration.TotalMinutes
            }
            else {
                "{0:N1} seconds" -f $Duration.TotalSeconds
            }
            Write-Host "  $paddedDuration : " -ForegroundColor DarkGray -NoNewline
            Write-Host $durationStr -ForegroundColor Cyan
        }

        Write-Host ""

        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message "Result summary displayed" -Data @{
            Title       = $Title
            ResultCount = $Results.Count
            Total       = $total
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error in Show-ResultSummary: $_"
        # Fallback to simple display
        Write-Host "`n$Title" -ForegroundColor Cyan
        Write-Host ($Results | Out-String)
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Starts a countdown menu with user input
#>
function Start-CountdownMenu {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 300)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [int]$DefaultOption,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [array]$ValidOptions
    )

    try {
        $selection = $null
        $lastDisplayedTime = -1

        Write-Host "Auto-selecting option [$DefaultOption] in " -ForegroundColor Gray -NoNewline

        $startTime = Get-Date

        while ($true) {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            $timeLeft = [math]::Max(0, $CountdownSeconds - [int]$elapsed)

            # Update display only when time changes
            if ($timeLeft -ne $lastDisplayedTime) {
                if ($lastDisplayedTime -ge 0) {
                    # Clear previous display
                    $clearLength = $lastDisplayedTime.ToString().Length + 4
                    Write-Host ("`b" * $clearLength) -NoNewline
                    Write-Host (" " * $clearLength) -NoNewline
                    Write-Host ("`b" * $clearLength) -NoNewline
                }
                Write-Host "$timeLeft" -ForegroundColor Yellow -NoNewline
                Write-Host "... " -ForegroundColor Gray -NoNewline
                $lastDisplayedTime = $timeLeft
            }

            # Check if countdown expired
            if ($timeLeft -le 0) {
                break
            }

            # Check for user input (check multiple times per second for responsiveness)
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Handle ESC key to abort
                if ($key.Key -eq 'Escape') {
                    Write-Host "`n`nOperation cancelled by user" -ForegroundColor Yellow
                    Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message 'User cancelled menu selection with ESC'
                    throw "User cancelled operation"
                }

                # Handle Enter key - use default option
                if ($key.Key -eq 'Enter' -or $key.KeyChar -eq [char]13) {
                    $selection = $DefaultOption
                    Write-Host "`n`nSelected: $selection (default)" -ForegroundColor Green
                    return $selection
                }

                $userInput = $key.KeyChar.ToString().ToUpper()

                # Support keyboard shortcuts
                if ($userInput -eq 'N' -and 1 -in $ValidOptions) {
                    $selection = 1
                    Write-Host "`n`nSelected: Execute all tasks" -ForegroundColor Green
                    return $selection
                }
                elseif ($userInput -match '^\d$') {
                    $inputNum = [int]$userInput
                    if ($inputNum -in $ValidOptions) {
                        $selection = $inputNum
                        Write-Host "`n`nSelected: $selection" -ForegroundColor Green
                        return $selection
                    }
                    else {
                        Write-Host "`n`nInvalid option: $inputNum (Valid: $($ValidOptions -join ', '))" -ForegroundColor Red
                        Write-Host "Auto-selecting option [$DefaultOption] in " -ForegroundColor Gray -NoNewline
                        $lastDisplayedTime = -1
                    }
                }
            }

            Start-Sleep -Milliseconds 100
        }

        # Countdown expired - use default
        if ($null -eq $selection) {
            $selection = $DefaultOption
            Write-Host "`n`nAuto-selected: $selection" -ForegroundColor Cyan
        }

        return $selection
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error in Start-CountdownMenu: $_"
        throw
    }
}

<#
.SYNOPSIS
    Starts a countdown input with default value
#>
function Start-CountdownInput {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 300)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultValue
    )

    try {
        $timeLeft = $CountdownSeconds
        $userInput = ""
        $lastDisplayedTime = -1

        Write-Host "Auto-selecting '$DefaultValue' in " -ForegroundColor Gray -NoNewline

        $startTime = Get-Date

        while ($true) {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            $timeLeft = [math]::Max(0, $CountdownSeconds - [int]$elapsed)

            # Update display only when time changes
            if ($timeLeft -ne $lastDisplayedTime) {
                if ($lastDisplayedTime -ge 0) {
                    # Clear previous display
                    $clearLength = $lastDisplayedTime.ToString().Length + 4
                    Write-Host ("`b" * $clearLength) -NoNewline
                    Write-Host (" " * $clearLength) -NoNewline
                    Write-Host ("`b" * $clearLength) -NoNewline
                }
                Write-Host "$timeLeft" -ForegroundColor Yellow -NoNewline
                Write-Host "... " -ForegroundColor Gray -NoNewline
                $lastDisplayedTime = $timeLeft
            }

            # Check if countdown expired
            if ($timeLeft -le 0) {
                break
            }

            # Check for user input (check multiple times per second for responsiveness)
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Handle ESC key to abort
                if ($key.Key -eq 'Escape') {
                    Write-Host "`n`nOperation cancelled by user" -ForegroundColor Yellow
                    Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message 'User cancelled input with ESC'
                    throw "User cancelled operation"
                }

                # Handle Enter key - submit input or use default
                if ($key.Key -eq 'Enter' -or $key.KeyChar -eq [char]13) {
                    if ([string]::IsNullOrWhiteSpace($userInput)) {
                        $userInput = $DefaultValue
                        Write-Host "`n`nSelected: $userInput (default)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "`n`nSelected: $userInput" -ForegroundColor Green
                    }
                    return $userInput
                }
                elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                    $userInput = $userInput.Substring(0, $userInput.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
                elseif ($key.KeyChar -match '[a-zA-Z0-9,\s-]') {
                    # Support ranges like 1-5
                    $userInput += $key.KeyChar
                    Write-Host $key.KeyChar -NoNewline -ForegroundColor White
                }
            }

            Start-Sleep -Milliseconds 100
        }

        # Countdown expired - use default value
        if ([string]::IsNullOrWhiteSpace($userInput)) {
            $userInput = $DefaultValue
            Write-Host "`n`nAuto-selected: $userInput" -ForegroundColor Cyan
        }
        else {
            Write-Host "`n`nSelected: $userInput" -ForegroundColor Green
        }

        return $userInput
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error in Start-CountdownInput: $_"
        throw
    }
}

<#
.SYNOPSIS
    Converts comma-separated task numbers into an array
#>
function ConvertFrom-TaskNumbers {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$TaskInput,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int]$MaxTasks
    )

    try {
        $selectedTasks = @()

        if ([string]::IsNullOrWhiteSpace($TaskInput)) {
            Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message 'Empty task input provided'
            return $selectedTasks
        }

        # Parse comma-separated task numbers and ranges
        $taskNumbers = $TaskInput -split ',' | ForEach-Object { $_.Trim() }

        foreach ($num in $taskNumbers) {
            # Handle range notation (e.g., 1-5)
            if ($num -match '^(\d+)-(\d+)$') {
                $rangeStart = [int]$Matches[1]
                $rangeEnd = [int]$Matches[2]

                if ($rangeStart -gt $rangeEnd) {
                    Write-Host "Warning: Invalid range '$num' (start must be <= end)" -ForegroundColor Yellow
                    Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message "Invalid range: $num"
                    continue
                }

                if ($rangeStart -lt 1 -or $rangeEnd -gt $MaxTasks) {
                    Write-Host "Warning: Range '$num' exceeds valid bounds (1-$MaxTasks)" -ForegroundColor Yellow
                    Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message "Range out of bounds: $num"
                    continue
                }

                # Add all numbers in range
                for ($i = $rangeStart; $i -le $rangeEnd; $i++) {
                    $selectedTasks += $i
                }

                Write-Host "Range expanded: $num -> $($rangeStart..$rangeEnd -join ', ')" -ForegroundColor Gray
            }
            # Handle single number
            elseif ($num -match '^\d+$') {
                $taskIndex = [int]$num
                if ($taskIndex -ge 1 -and $taskIndex -le $MaxTasks) {
                    $selectedTasks += $taskIndex
                }
                else {
                    Write-Host "Warning: Task number $taskIndex is out of range (1-$MaxTasks)" -ForegroundColor Yellow
                    Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message "Task number out of range: $taskIndex"
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($num)) {
                Write-Host "Warning: Invalid task number '$num' (use numbers, ranges like 1-5, or commas)" -ForegroundColor Yellow
                Write-LogEntry -Level 'WARNING' -Component 'USER-INTERFACE' -Message "Invalid task number format: $num"
            }
        }

        $uniqueTasks = $selectedTasks | Sort-Object | Get-Unique
        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message "Parsed task selection" -Data @{
            Input       = $TaskInput
            ParsedCount = $uniqueTasks.Count
            Tasks       = ($uniqueTasks -join ',')
        }

        return $uniqueTasks
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'USER-INTERFACE' -Message "Error parsing task numbers: $_"
        return @()
    }
}

#endregion

<#
.SYNOPSIS
    Shows the Type1 module selection menu with countdown

.DESCRIPTION
    Displays an interactive menu for selecting Type1 (audit/inventory) modules to execute.
    Option 0 runs all Type1 modules (default). Individual modules can be selected by number.
    Auto-selects option 0 after countdown expires.

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer (default: 10)

.PARAMETER AvailableModules
    Array of available Type1 modules to display

.OUTPUTS
    [array] Selected module indices (0 = all modules)

.EXAMPLE
    $selection = Show-Type1ModuleMenu -CountdownSeconds 10 -AvailableModules $type1Modules
    # Returns: @(0) for all modules, or @(1,3,5) for specific selections

.NOTES
    Phase 1 Implementation - Interactive Type1 Module Selection
    Integrates with MaintenanceOrchestrator.ps1 for pre-execution audit phase
#>
function Show-Type1ModuleMenu {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [int]$CountdownSeconds = 10,

        [Parameter()]
        [array]$AvailableModules = @()
    )

    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'Type1ModuleMenu' -Component 'USER-INTERFACE'
    }
    catch {
        Write-Verbose "Performance tracking unavailable"
    }

    Write-Host "`n" -NoNewline
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "    STAGE 1: SYSTEM INVENTORY (Type1 Modules)" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select modules to execute:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [0] Run All Type1 Modules (Default)" -ForegroundColor Green
    Write-Host ""

    # Display available Type1 modules
    if ($AvailableModules.Count -gt 0) {
        for ($i = 0; $i -lt $AvailableModules.Count; $i++) {
            $module = $AvailableModules[$i]
            $moduleNumber = "[$($i+1)]"

            if ($module -is [hashtable] -and $module.ContainsKey('Name')) {
                $moduleName = $module.Name
                $moduleDesc = if ($module.ContainsKey('Description')) { $module.Description } else { "Audit module" }
                Write-Host "  $moduleNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "$moduleName" -ForegroundColor White
                Write-Host "      - $moduleDesc" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  $moduleNumber " -ForegroundColor Cyan -NoNewline
                Write-Host "$module" -ForegroundColor White
            }
        }
        Write-Host ""
    }

    Write-Host "Tip: Enter 0 for all, or comma-separated numbers (e.g., 1,3,5)" -ForegroundColor DarkGray
    Write-Host ""

    # Countdown with auto-selection
    $selection = Start-CountdownInput -CountdownSeconds $CountdownSeconds -DefaultValue "0"

    # Parse selection
    $selectedIndices = @()

    if ($selection -eq "0") {
        # All modules
        $selectedIndices = @(0)
        Write-Host ""
        Write-Host "Selected: All Type1 modules ($($AvailableModules.Count) modules)" -ForegroundColor Green
    }
    else {
        # Parse comma-separated list
        try {
            $numbers = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
            $validNumbers = $numbers | Where-Object { $_ -ge 1 -and $_ -le $AvailableModules.Count }

            if ($validNumbers.Count -eq 0) {
                Write-Host ""
                Write-Host "No valid selections - defaulting to all modules" -ForegroundColor Yellow
                $selectedIndices = @(0)
            }
            else {
                $selectedIndices = $validNumbers
                Write-Host ""
                Write-Host "Selected Type1 modules: $($selectedIndices -join ', ')" -ForegroundColor Green
            }
        }
        catch {
            Write-Host ""
            Write-Host "Invalid input - defaulting to all modules" -ForegroundColor Yellow
            $selectedIndices = @(0)
        }
    }

    # Complete performance tracking
    try {
        Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $selectedIndices.Count
    }
    catch {
        Write-Verbose "Performance tracking completion failed"
    }

    Write-Host ""
    return $selectedIndices
}

# Export public functions
Export-ModuleMember -Function @(
    'Show-MainMenu',
    'Show-Type1ModuleMenu',
    'Show-ConfirmationDialog',
    'Show-Progress',
    'Show-ProgressBar',
    'Show-ResultSummary',
    'ConvertFrom-TaskNumbers',
    'Start-CountdownInput'  # FIX: Export countdown function for non-interactive mode
)





