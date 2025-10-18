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

# Import LoggingManager for structured logging (with graceful fallback)
try {
    $loggingManagerPath = Join-Path $PSScriptRoot 'LoggingManager.psm1'
    if (Test-Path $loggingManagerPath) {
        Import-Module $loggingManagerPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    # LoggingManager not available, continue without structured logging
}

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
        [int]$CountdownSeconds = 20,

        [Parameter()]
        [int]$DefaultOption = 1,

        [Parameter()]
        [array]$AvailableTasks = @()
    )
    
    # Start performance tracking for menu display
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'MainMenuDisplay' -Component 'MENU-SYSTEM'
        Write-LogEntry -Level 'INFO' -Component 'MENU-SYSTEM' -Message 'Displaying main menu' -Data @{ CountdownSeconds = $CountdownSeconds; DefaultOption = $DefaultOption }
    } catch {
        # LoggingManager not available, continue with standard logging
    }

    Write-Host "`n" -NoNewline
    Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
    Write-Host "    WINDOWS MAINTENANCE AUTOMATION - EXECUTION MODE SELECTION    " -BackgroundColor DarkBlue
    Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "🔧 Please select execution mode:" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "  [1] Execute Script Normally (Unattended) [DEFAULT]" -InformationAction Continue
    Write-Information "      → Performs actual system changes unattended" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "  [2] Execute in Dry-Run Mode" -InformationAction Continue
    Write-Information "      → Simulates changes without modifying the system" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "───────────────────────────────────────────────────────────────" -InformationAction Continue

    $selection = Start-CountdownSelection -CountdownSeconds $CountdownSeconds -DefaultOption $DefaultOption -OptionsCount 2

    Write-Information "" -InformationAction Continue
    
    # Initialize result structure
    $result = @{
        Mode = 'Execute'
        DryRun = $false
        SelectedTasks = @()
        UserInteracted = $false
    }
    
    # Handle main menu selection and show submenus
    switch ($selection) {
        1 {
            Write-Host "✓ Selected: Execute Script Normally (Unattended)" -ForegroundColor Green
            $result.DryRun = $false
            $result.UserInteracted = $true
            
            # Show submenu for normal execution
            $subResult = Show-ExecutionSubmenu -CountdownSeconds $CountdownSeconds -ExecutionMode 'Normal' -AvailableTasks $AvailableTasks
            $result.SelectedTasks = $subResult.SelectedTasks
        }
        2 {
            Write-Host "✓ Selected: Execute in Dry-Run Mode" -ForegroundColor Green
            $result.DryRun = $true
            $result.UserInteracted = $true
            
            # Show submenu for dry-run execution
            $subResult = Show-ExecutionSubmenu -CountdownSeconds $CountdownSeconds -ExecutionMode 'DryRun' -AvailableTasks $AvailableTasks
            $result.SelectedTasks = $subResult.SelectedTasks
        }
        default {
            Write-Host "✓ Default: Execute Script Normally (Unattended)" -ForegroundColor Green
            $result.DryRun = $false
            $result.UserInteracted = $false
            
            # Auto-select all tasks for default behavior
            $result.SelectedTasks = 1..$AvailableTasks.Count
        }
    }
    
    # Complete performance tracking and structured logging
    try {
        Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData @{
            SelectedOption = $selection
            Mode = $result.Mode
            DryRun = $result.DryRun
            TaskCount = $result.SelectedTasks.Count
            CountdownUsed = $true
        }
        Write-LogEntry -Level 'SUCCESS' -Component 'MENU-SYSTEM' -Message 'Main menu selection completed' -Data @{ SelectedOption = $selection; Mode = $result.Mode; DryRun = $result.DryRun; TaskCount = $result.SelectedTasks.Count }
    } catch {
        # LoggingManager not available, continue with standard logging
    }
    
    return $result
}

<#
.SYNOPSIS
    Shows the execution submenu for task selection

.DESCRIPTION
    Displays options for executing all tasks or selecting specific task numbers.
    This is called after the main execution mode is selected.

.PARAMETER CountdownSeconds
    Number of seconds for countdown timer

.PARAMETER ExecutionMode
    The execution mode (Normal or DryRun)

.PARAMETER AvailableTasks
    Array of available tasks

.EXAMPLE
    Show-ExecutionSubmenu -CountdownSeconds 20 -ExecutionMode 'Normal' -AvailableTasks $tasks
#>
function Show-ExecutionSubmenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$CountdownSeconds,

        [Parameter(Mandatory)]
        [ValidateSet('Normal', 'DryRun')]
        [string]$ExecutionMode,

        [Parameter()]
        [array]$AvailableTasks = @()
    )

    try {
        Write-Verbose "Displaying execution submenu for $ExecutionMode mode"
        
        $modeText = if ($ExecutionMode -eq 'DryRun') { 'DRY-RUN' } else { 'LIVE' }
        $modeColor = if ($ExecutionMode -eq 'DryRun') { 'Cyan' } else { 'Green' }

        Write-Host "`n" -NoNewline
        Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
        Write-Host "    TASK SELECTION - $($modeText.ToUpper()) EXECUTION MODE" -BackgroundColor DarkBlue
        Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Information "📋 Please select tasks to execute:" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Information "  [1] Execute All Tasks Unattended [DEFAULT]" -InformationAction Continue
        Write-Information "      → Runs all $($AvailableTasks.Count) available maintenance tasks automatically" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        Write-Host "  [2] Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
        Write-Host "      → Choose specific tasks by number (comma-separated input)" -ForegroundColor $modeColor
        Write-Information "" -InformationAction Continue

        if ($AvailableTasks.Count -gt 0) {
            Write-Information "Available Tasks:" -InformationAction Continue
            Write-Information "───────────────────────────────────────────────────────────────" -InformationAction Continue
            for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
                $task = $AvailableTasks[$i]
                Write-Information "  [$($i + 1)] $($task.Name) - $($task.Description)" -InformationAction Continue
            }
            Write-Information "───────────────────────────────────────────────────────────────" -InformationAction Continue
            Write-Information "" -InformationAction Continue
        }

        $selection = Start-CountdownSelection -CountdownSeconds $CountdownSeconds -DefaultOption 1 -OptionsCount 2

        $result = @{
            SelectedTasks = @()
            TaskSelectionMode = 'All'
        }

        switch ($selection) {
            1 {
                Write-Host "✓ Selected: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
                $result.SelectedTasks = 1..$AvailableTasks.Count
                $result.TaskSelectionMode = 'All'
            }
            2 {
                Write-Host "✓ Selected: Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
                # Prompt for specific task numbers
                $result = Get-SpecificTaskNumbers -AvailableTasks $AvailableTasks -ModeColor $modeColor
            }
            default {
                Write-Host "✓ Default: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
                $result.SelectedTasks = 1..$AvailableTasks.Count
                $result.TaskSelectionMode = 'All'
            }
        }

        return $result

    } catch {
        Write-Error "Failed to display execution submenu: $_"
        # Return default: all tasks
        return @{
            SelectedTasks = 1..$AvailableTasks.Count
            TaskSelectionMode = 'All'
        }
    }
}

<#
.SYNOPSIS
    Prompts user for specific task numbers

.DESCRIPTION
    Allows user to input specific task numbers to execute

.PARAMETER AvailableTasks
    Array of available tasks

.PARAMETER ModeColor
    Color for output text
#>
function Get-SpecificTaskNumbers {
    [CmdletBinding()]
    param(
        [Parameter()]
        [array]$AvailableTasks = @(),

        [Parameter()]
        [string]$ModeColor = 'Green'
    )

    $result = @{
        SelectedTasks = @()
        TaskSelectionMode = 'Specific'
    }

    try {
        Write-Information "" -InformationAction Continue
        Write-Host "Enter task numbers to execute (comma-separated, e.g., 1,3,5): " -NoNewline -ForegroundColor $ModeColor
        
        $input = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "No input provided. Selecting all tasks." -ForegroundColor Yellow
            $result.SelectedTasks = 1..$AvailableTasks.Count
            $result.TaskSelectionMode = 'All'
        } else {
            # Parse comma-separated numbers
            $taskNumbers = @()
            $inputParts = $input -split ',' | ForEach-Object { $_.Trim() }
            
            foreach ($part in $inputParts) {
                try {
                    $number = [int]$part
                    if ($number -ge 1 -and $number -le $AvailableTasks.Count) {
                        $taskNumbers += $number
                    } else {
                        Write-Warning "Task number $number is out of range (1-$($AvailableTasks.Count)). Skipping."
                    }
                } catch {
                    Write-Warning "Invalid task number '$part'. Skipping."
                }
            }
            
            if ($taskNumbers.Count -gt 0) {
                $result.SelectedTasks = $taskNumbers | Sort-Object -Unique
                Write-Host "✓ Selected tasks: $($result.SelectedTasks -join ', ')" -ForegroundColor $ModeColor
            } else {
                Write-Host "No valid task numbers provided. Selecting all tasks." -ForegroundColor Yellow
                $result.SelectedTasks = 1..$AvailableTasks.Count
                $result.TaskSelectionMode = 'All'
            }
        }
    } catch {
        Write-Error "Error processing task selection: $_"
        # Fallback to all tasks
        $result.SelectedTasks = 1..$AvailableTasks.Count
        $result.TaskSelectionMode = 'All'
    }

    return $result
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
    
    # Start performance tracking for task selection menu
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'TaskSelectionMenuDisplay' -Component 'MENU-SYSTEM'
        Write-LogEntry -Level 'INFO' -Component 'MENU-SYSTEM' -Message 'Displaying task selection menu' -Data @{ IsDryRun = $IsDryRun; AvailableTasksCount = $AvailableTasks.Count; CountdownSeconds = $CountdownSeconds; DefaultOption = $DefaultOption }
    } catch {
        # LoggingManager not available, continue with standard logging
    }

    $modeText = if ($IsDryRun) { "DRY-RUN" } else { "EXECUTION" }
    $modeColor = if ($IsDryRun) { "Blue" } else { "Green" }

    Write-Information "" -InformationAction Continue
    Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information "    TASK SELECTION - $modeText MODE" -InformationAction Continue
    Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "📋 Please select tasks to execute:" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "  [1] Execute All Tasks Unattended [DEFAULT]" -InformationAction Continue
    Write-Information "      → Runs all $($AvailableTasks.Count) available maintenance tasks automatically" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Host "  [2] Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
    Write-Information "      → Choose specific tasks by number (comma-separated input)" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "Available Tasks:" -InformationAction Continue
    Write-Information "───────────────────────────────────────────────────────────────" -InformationAction Continue

    for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
        $taskNum = $i + 1
        $task = $AvailableTasks[$i]
        $taskName = if ($task.Name) { $task.Name } else { "Task $taskNum" }
        $taskDesc = if ($task.Description) { " - $($task.Description)" } else { "" }

        Write-Information "  [$taskNum] $taskName$taskDesc" -InformationAction Continue
    }

    Write-Information "───────────────────────────────────────────────────────────────" -InformationAction Continue

    $selection = Start-CountdownSelection -CountdownSeconds $CountdownSeconds -DefaultOption $DefaultOption -OptionsCount 2

    Write-Information "" -InformationAction Continue
    switch ($selection) {
        1 {
            Write-Host "✓ Selected: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
            $result = @{
                SelectionType = 'All'
                TaskNumbers   = @(1..$AvailableTasks.Count)
                Tasks         = $AvailableTasks
            }
            
            # Complete performance tracking if available
            try {
                if ($perfContext) {
                    Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData $result
                }
            } catch {
                # LoggingManager not available, continue
            }
            
            return $result
        }
        2 {
            Write-Host "✓ Selected: Execute Only Inserted Task Numbers" -ForegroundColor $modeColor
            $selectedTasks = Get-TaskNumberSelection -AvailableTasks $AvailableTasks
            
            # Complete performance tracking if available
            try {
                if ($perfContext) {
                    Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData $selectedTasks
                }
            } catch {
                # LoggingManager not available, continue
            }
            
            return $selectedTasks
        }
        default {
            Write-Host "✓ Default: Execute All Tasks Unattended ($($AvailableTasks.Count) tasks)" -ForegroundColor $modeColor
            $result = @{
                SelectionType = 'All'
                TaskNumbers   = @(1..$AvailableTasks.Count)
                Tasks         = $AvailableTasks
            }
            
            # Complete performance tracking if available
            try {
                if ($perfContext) {
                    Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData $result
                }
            } catch {
                # LoggingManager not available, continue
            }
            
            return $result
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
<#
.SYNOPSIS
    Prompts user to select specific maintenance tasks by number

.DESCRIPTION
    Interactive function that prompts the user to enter task numbers for selective
    execution. Validates input, handles comma-separated lists, and provides feedback
    for invalid selections. Continues prompting until valid task numbers are provided.

.PARAMETER AvailableTasks
    Array of available maintenance tasks to choose from

.OUTPUTS
    [int[]] Array of selected task numbers (1-based indexing)

.EXAMPLE
    $selectedTasks = Get-TaskNumberSelection -AvailableTasks $tasks
    
.NOTES
    Part of the MenuSystem module for interactive user input handling.
    Supports comma-separated input and provides validation feedback.
#>
function Get-TaskNumberSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$AvailableTasks
    )

    $maxTaskNumber = $AvailableTasks.Count

    do {
        Write-Information "" -InformationAction Continue
        Write-Information "📝 Enter task numbers (comma-separated, e.g., 1,3,5,7): " -InformationAction Continue
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            Write-Information "❌ No input provided. Please enter task numbers or press Ctrl+C to cancel." -InformationAction Continue
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
            Write-Information "Invalid task numbers: $($invalidNumbers -join ', '). Please use numbers between 1 and $maxTaskNumber." -InformationAction Continue
        }

    } while (-not $validInput)

    # Remove duplicates and sort
    $taskNumbers = $taskNumbers | Sort-Object -Unique

    # Get corresponding tasks
    $selectedTasks = @()
    foreach ($taskNum in $taskNumbers) {
        $selectedTasks += $AvailableTasks[$taskNum - 1]
    }

    Write-Information "" -InformationAction Continue
    Write-Information "✓ Selected Tasks: " -InformationAction Continue
    Write-Information "($($taskNumbers -join ', '))" -InformationAction Continue
    foreach ($taskNum in $taskNumbers) {
        $task = $AvailableTasks[$taskNum - 1]
        $taskName = if ($task.Name) { $task.Name } else { "Task $taskNum" }
        Write-Information "  [$taskNum] $taskName" -InformationAction Continue
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

    Write-Information "" -InformationAction Continue

    for ($i = $CountdownSeconds; $i -gt 0; $i--) {
        # Check for user input
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $selection = $null

            # Handle number key input
            if ($key.KeyChar -match '^\d$') {
                $selection = [int]$key.KeyChar.ToString()
                if ($selection -ge 1 -and $selection -le $OptionsCount) {
                    Write-Host ""  # Clear the countdown line
                    return $selection
                }
            }

            # Handle Enter key (select default)
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ""  # Clear the countdown line
                return $DefaultOption
            }
        }

        # Display countdown on the same line using carriage return
        Write-Host "`rCountdown: $i seconds (Press 1-$OptionsCount to select, Enter for default)" -NoNewline -ForegroundColor Yellow

        Start-Sleep -Seconds 1
    }

    Write-Host ""  # Move to next line after countdown completes
    Write-Information "⏱️ Time expired! Selecting default option [$DefaultOption]" -InformationAction Continue
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

    Write-Information "" -InformationAction Continue
    Write-Information "⚠️  " -InformationAction Continue
    Write-Information $Message -InformationAction Continue
    Write-Information "" -InformationAction Continue

    $defaultText = if ($DefaultChoice -eq 'Y') { "Yes" } else { "No" }
    Write-Information "Countdown starting..." -InformationAction Continue

    for ($i = $CountdownSeconds; $i -gt 0; $i--) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.KeyChar.ToString().ToUpper()) {
                'Y' {
                    Write-Information "" -InformationAction Continue
                    Write-Information "✓ Confirmed: Yes" -InformationAction Continue
                    return $true
                }
                'N' {
                    Write-Information "" -InformationAction Continue
                    Write-Information "✗ Confirmed: No" -InformationAction Continue
                    return $false
                }
            }

            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Information "" -InformationAction Continue
                Write-Information "✓ Default: $defaultText" -InformationAction Continue
                return ($DefaultChoice -eq 'Y')
            }
        }

        Write-Information "`rCountdown: $i seconds (Y/N, Enter for default [$DefaultChoice])" -InformationAction Continue

        Start-Sleep -Seconds 1
    }

    Write-Information "" -InformationAction Continue
    Write-Information "⏱️ Time expired! Default: $defaultText" -InformationAction Continue
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
    'Show-ExecutionSubmenu',
    'Get-SpecificTaskNumbers',
    'Show-TaskSelectionMenu',
    'Get-TaskNumberSelection',
    'Start-CountdownSelection',
    'Show-ConfirmationDialog',
    'Set-MenuConfiguration',
    'Get-MenuConfiguration'
)


