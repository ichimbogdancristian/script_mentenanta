#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive Menu System Module for Windows Maintenance Automation

.DESCRIPTION
    Provides countdown-based interactive menus with automatic fallback to default options.
    Supports unattended execution, dry-run modes, and task selection capabilities.

.NOTES
    Module Type: Core Infrastructure
    Dependencies: None (standalone)
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Module variables
$script:MenuConfig = @{
    CountdownSeconds  = 20
    DefaultMode       = 'unattended'
    EnableDryRun      = $true
    AutoSelectDefault = $true
}

#region Public Functions

<#
.SYNOPSIS
    Shows the main execution menu with countdown timer

.DESCRIPTION
    Displays a menu allowing the user to choose between unattended execution and dry-run mode.
    Features a 20-second countdown with automatic selection of the default option.

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer (default: 20)

.PARAMETER DefaultOption
    The default option to select when countdown expires (default: 1)

.EXAMPLE
    $selection = Show-MainMenu
    # Shows main menu and returns user selection or default after countdown
#>
function Show-MainMenu {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$CountdownSeconds = $script:MenuConfig.CountdownSeconds,

        [Parameter()]
        [int]$DefaultOption = 1
    )

    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    WINDOWS MAINTENANCE AUTOMATION - EXECUTION MODE SELECTION    " -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🔧 Please select execution mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Execute Script Normally (Unattended) " -ForegroundColor Green -NoNewline
    Write-Host "[DEFAULT]" -ForegroundColor Cyan
    Write-Host "      → Performs actual system changes unattended" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] Execute in Dry-Run Mode" -ForegroundColor Blue
    Write-Host "      → Simulates changes without modifying the system" -ForegroundColor Gray
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

    $selection = Start-CountdownSelection -CountdownSeconds $CountdownSeconds -DefaultOption $DefaultOption -OptionsCount 2

    Write-Host ""
    switch ($selection) {
        1 {
            Write-Host "✓ Selected: Execute Script Normally (Unattended)" -ForegroundColor Green
            return @{ Mode = 'Execute'; DryRun = $false }
        }
        2 {
            Write-Host "✓ Selected: Execute in Dry-Run Mode" -ForegroundColor Blue
            return @{ Mode = 'Execute'; DryRun = $true }
        }
        default {
            Write-Host "✓ Default: Execute Script Normally (Unattended)" -ForegroundColor Green
            return @{ Mode = 'Execute'; DryRun = $false }
        }
    }
}

<#
.SYNOPSIS
    Shows the task execution submenu

.DESCRIPTION
    Displays options for executing all tasks or selecting specific task numbers.
    Supports both normal execution and dry-run modes.

.PARAMETER IsDryRun
    Whether this is for dry-run mode (affects display text)

.PARAMETER AvailableTasks
    Array of available tasks to display

.EXAMPLE
    $taskSelection = Show-TaskSelectionMenu -IsDryRun $false -AvailableTasks $tasks
#>
function Show-TaskSelectionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$IsDryRun,

        [Parameter(Mandatory)]
        [Array]$AvailableTasks,

        [Parameter()]
        [int]$CountdownSeconds = $script:MenuConfig.CountdownSeconds,

        [Parameter()]
        [int]$DefaultOption = 1
    )

    $modeText = if ($IsDryRun) { "DRY-RUN" } else { "EXECUTION" }
    $modeColor = if ($IsDryRun) { "Blue" } else { "Green" }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    TASK SELECTION - $modeText MODE" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📋 Please select tasks to execute:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Execute All Tasks Unattended " -ForegroundColor $modeColor -NoNewline
    Write-Host "[DEFAULT]" -ForegroundColor Cyan
    Write-Host "      → Runs all $($AvailableTasks.Count) available maintenance tasks automatically" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
    Write-Host "      → Choose specific tasks by number (comma-separated input)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Available Tasks:" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

    for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
        $taskNum = $i + 1
        $task = $AvailableTasks[$i]
        $taskName = if ($task.Name) { $task.Name } else { "Task $taskNum" }
        $taskDesc = if ($task.Description) { " - $($task.Description)" } else { "" }

        Write-Host "  [$taskNum] " -ForegroundColor White -NoNewline
        Write-Host "$taskName" -ForegroundColor Cyan -NoNewline
        Write-Host "$taskDesc" -ForegroundColor Gray
    }

    Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

    $selection = Start-CountdownSelection -CountdownSeconds $CountdownSeconds -DefaultOption $DefaultOption -OptionsCount 2

    Write-Host ""
    switch ($selection) {
        1 {
            Write-Host "✓ Selected: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
            return @{
                SelectionType = 'All'
                TaskNumbers   = @(1..$AvailableTasks.Count)
                Tasks         = $AvailableTasks
            }
        }
        2 {
            Write-Host "✓ Selected: Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
            $selectedTasks = Get-TaskNumberSelection -AvailableTasks $AvailableTasks
            return $selectedTasks
        }
        default {
            Write-Host "✓ Default: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
            return @{
                SelectionType = 'All'
                TaskNumbers   = @(1..$AvailableTasks.Count)
                Tasks         = $AvailableTasks
            }
        }
    }
}

<#
.SYNOPSIS
    Gets specific task number selection from user

.DESCRIPTION
    Prompts the user to enter specific task numbers (comma-separated) and validates the input.

.PARAMETER AvailableTasks
    Array of available tasks for validation

.EXAMPLE
    $selection = Get-TaskNumberSelection -AvailableTasks $tasks
#>
function Get-TaskNumberSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$AvailableTasks
    )

    $maxTaskNumber = $AvailableTasks.Count

    do {
        Write-Host ""
        Write-Host "📝 Enter task numbers (comma-separated, e.g., 1,3,5,7): " -ForegroundColor Yellow -NoNewline
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            Write-Host "❌ No input provided. Please enter task numbers or press Ctrl+C to cancel." -ForegroundColor Red
            continue
        }

        # Parse and validate task numbers
        $taskNumbers = @()
        $invalidNumbers = @()
        $validInput = $true

        $inputNumbers = $userInput -split ',' | ForEach-Object { $_.Trim() }

        foreach ($num in $inputNumbers) {
            if ($num -match '^\d+$') {
                $taskNum = [int]$num
                if ($taskNum -ge 1 -and $taskNum -le $maxTaskNumber) {
                    $taskNumbers += $taskNum
                }
                else {
                    $invalidNumbers += $num
                    $validInput = $false
                }
            }
            else {
                $invalidNumbers += $num
                $validInput = $false
            }
        }

        if (-not $validInput) {
            Write-Host "Invalid task numbers: $($invalidNumbers -join ', '). Please use numbers between 1 and $maxTaskNumber." -ForegroundColor Red
        }

    } while (-not $validInput)

    # Remove duplicates and sort
    $taskNumbers = $taskNumbers | Sort-Object -Unique

    # Get corresponding tasks
    $selectedTasks = @()
    foreach ($taskNum in $taskNumbers) {
        $selectedTasks += $AvailableTasks[$taskNum - 1]
    }

    Write-Host ""
    Write-Host "✓ Selected Tasks: " -ForegroundColor Green -NoNewline
    Write-Host "($($taskNumbers -join ', '))" -ForegroundColor Cyan
    foreach ($taskNum in $taskNumbers) {
        $task = $AvailableTasks[$taskNum - 1]
        $taskName = if ($task.Name) { $task.Name } else { "Task $taskNum" }
        Write-Host "  [$taskNum] $taskName" -ForegroundColor White
    }

    return @{
        SelectionType = 'Specific'
        TaskNumbers   = $taskNumbers
        Tasks         = $selectedTasks
    }
}

<#
.SYNOPSIS
    Starts a countdown timer with user input capability

.DESCRIPTION
    Displays a countdown timer while allowing the user to make a selection.
    Automatically selects the default option when the timer expires.

.PARAMETER CountdownSeconds
    Number of seconds for countdown

.PARAMETER DefaultOption
    Default option to select when countdown expires

.PARAMETER OptionsCount
    Total number of available options (for validation)

.EXAMPLE
    $selection = Start-CountdownSelection -CountdownSeconds 20 -DefaultOption 1 -OptionsCount 2
#>
function Start-CountdownSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [int]$DefaultOption,

        [Parameter(Mandatory)]
        [int]$OptionsCount
    )

    Write-Host ""
    Write-Host "Countdown: " -ForegroundColor Yellow -NoNewline

    for ($i = $CountdownSeconds; $i -gt 0; $i--) {
        # Check for user input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $selection = $null

            # Handle number key input
            if ($key.KeyChar -match '^\d$') {
                $selection = [int]$key.KeyChar.ToString()
                if ($selection -ge 1 -and $selection -le $OptionsCount) {
                    Write-Host ""
                    return $selection
                }
            }

            # Handle Enter key (select default)
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ""
                return $DefaultOption
            }
        }

        # Display countdown
        Write-Host "`r" -NoNewline
        Write-Host "Countdown: " -ForegroundColor Yellow -NoNewline
        Write-Host "$i seconds " -ForegroundColor Red -NoNewline
        Write-Host "(Press 1-$OptionsCount to select, Enter for default)" -ForegroundColor Gray -NoNewline

        Start-Sleep -Seconds 1
    }

    Write-Host ""
    Write-Host "⏱️ Time expired! Selecting default option [$DefaultOption]" -ForegroundColor Yellow
    return $DefaultOption
}

<#
.SYNOPSIS
    Shows a confirmation dialog with countdown

.DESCRIPTION
    Displays a confirmation prompt with automatic "Yes" selection after countdown.

.PARAMETER Message
    The confirmation message to display

.PARAMETER CountdownSeconds
    Number of seconds for countdown (default: 10)

.PARAMETER DefaultChoice
    Default choice when countdown expires ('Y' or 'N', default: 'Y')

.EXAMPLE
    $confirmed = Show-ConfirmationDialog -Message "Continue with system changes?" -CountdownSeconds 10
#>
function Show-ConfirmationDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [int]$CountdownSeconds = 10,

        [Parameter()]
        [char]$DefaultChoice = 'Y'
    )

    Write-Host ""
    Write-Host "⚠️  " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor White
    Write-Host ""

    $defaultText = if ($DefaultChoice -eq 'Y') { "Yes" } else { "No" }
    Write-Host "Countdown: " -ForegroundColor Yellow -NoNewline

    for ($i = $CountdownSeconds; $i -gt 0; $i--) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.KeyChar.ToString().ToUpper()) {
                'Y' {
                    Write-Host ""
                    Write-Host "✓ Confirmed: Yes" -ForegroundColor Green
                    return $true
                }
                'N' {
                    Write-Host ""
                    Write-Host "✗ Confirmed: No" -ForegroundColor Red
                    return $false
                }
            }

            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ""
                Write-Host "✓ Default: $defaultText" -ForegroundColor Yellow
                return ($DefaultChoice -eq 'Y')
            }
        }

        Write-Host "`r" -NoNewline
        Write-Host "Countdown: " -ForegroundColor Yellow -NoNewline
        Write-Host "$i seconds " -ForegroundColor Red -NoNewline
        Write-Host "(Y/N, Enter for default [$DefaultChoice])" -ForegroundColor Gray -NoNewline

        Start-Sleep -Seconds 1
    }

    Write-Host ""
    Write-Host "⏱️ Time expired! Default: $defaultText" -ForegroundColor Yellow
    return ($DefaultChoice -eq 'Y')
}

#endregion

#region Module Configuration

<#
.SYNOPSIS
    Sets the module configuration

.DESCRIPTION
    Updates the module configuration with provided values.

.PARAMETER CountdownSeconds
    Default countdown seconds

.PARAMETER DefaultMode
    Default execution mode

.PARAMETER EnableDryRun
    Whether dry-run mode is enabled

.PARAMETER AutoSelectDefault
    Whether to auto-select default options
#>
function Set-MenuConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$CountdownSeconds,

        [Parameter()]
        [string]$DefaultMode,

        [Parameter()]
        [bool]$EnableDryRun,

        [Parameter()]
        [bool]$AutoSelectDefault
    )

    if ($PSBoundParameters.ContainsKey('CountdownSeconds')) {
        $script:MenuConfig.CountdownSeconds = $CountdownSeconds
    }

    if ($PSBoundParameters.ContainsKey('DefaultMode')) {
        $script:MenuConfig.DefaultMode = $DefaultMode
    }

    if ($PSBoundParameters.ContainsKey('EnableDryRun')) {
        $script:MenuConfig.EnableDryRun = $EnableDryRun
    }

    if ($PSBoundParameters.ContainsKey('AutoSelectDefault')) {
        $script:MenuConfig.AutoSelectDefault = $AutoSelectDefault
    }
}

<#
.SYNOPSIS
    Gets the current module configuration

.DESCRIPTION
    Returns the current module configuration settings.

.EXAMPLE
    $config = Get-MenuConfiguration
#>
function Get-MenuConfiguration {
    [CmdletBinding()]
    param()

    return $script:MenuConfig.Clone()
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Show-MainMenu',
    'Show-TaskSelectionMenu',
    'Get-TaskNumberSelection',
    'Start-CountdownSelection',
    'Show-ConfirmationDialog',
    'Set-MenuConfiguration',
    'Get-MenuConfiguration'
)
