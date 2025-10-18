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
        $perfContext = Start-PerformanceTracking -OperationName 'MainMenuDisplay' -Component 'USER-INTERFACE'
        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message 'Displaying main menu' -Data @{ CountdownSeconds = $CountdownSeconds; DefaultOption = $DefaultOption }
    }
    catch {
        # CoreInfrastructure not available, continue with standard logging
    }

    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "    Windows Maintenance Automation v2.1.1" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select execution mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Unattended mode (recommended)" -ForegroundColor Green
    Write-Host "  [2] Dry-run mode (simulate changes)" -ForegroundColor Cyan
    Write-Host "  [3] Task selection mode" -ForegroundColor Magenta
    Write-Host "  [4] Exit" -ForegroundColor Red
    Write-Host ""

    # Show available tasks if provided
    if ($AvailableTasks.Count -gt 0) {
        Write-Host "Available maintenance tasks:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
            Write-Host "  [$($i+1)] $($AvailableTasks[$i])" -ForegroundColor Gray
        }
        Write-Host ""
    }

    $selection = Start-CountdownMenu -CountdownSeconds $CountdownSeconds -DefaultOption $DefaultOption -ValidOptions @(1, 2, 3, 4)

    # Complete performance tracking
    try {
        Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $selection
    }
    catch {}

    return $selection
}

<#
.SYNOPSIS
    Shows task selection menu

.DESCRIPTION
    Displays a menu for selecting specific maintenance tasks to execute.

.PARAMETER AvailableTasks
    Array of available tasks to display

.PARAMETER CountdownSeconds
    Number of seconds for the countdown timer

.EXAMPLE
    $tasks = Show-TaskSelectionMenu -AvailableTasks $taskList
#>
function Show-TaskSelectionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$AvailableTasks,

        [Parameter()]
        [int]$CountdownSeconds = 30
    )

    try {
        Write-LogEntry -Level 'INFO' -Component 'USER-INTERFACE' -Message 'Displaying task selection menu' -Data @{ TaskCount = $AvailableTasks.Count }
    }
    catch {}

    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "    Task Selection Menu" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available maintenance tasks:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $AvailableTasks.Count; $i++) {
        Write-Host "  [$($i+1)] $($AvailableTasks[$i])" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  [A] All tasks (default)" -ForegroundColor Cyan
    Write-Host "  [C] Cancel" -ForegroundColor Red
    Write-Host ""
    Write-Host "Enter task numbers (comma-separated) or letter choice:" -ForegroundColor Yellow

    $userInput = Start-CountdownInput -CountdownSeconds $CountdownSeconds -DefaultValue "A"
    
    if ($userInput -eq "C" -or $userInput -eq "c") {
        return @()
    }
    
    if ($userInput -eq "A" -or $userInput -eq "a" -or [string]::IsNullOrWhiteSpace($userInput)) {
        return 1..$AvailableTasks.Count
    }

    # Parse comma-separated task numbers
    $selectedTasks = @()
    $taskNumbers = $userInput -split ',' | ForEach-Object { $_.Trim() }
    
    foreach ($num in $taskNumbers) {
        if ($num -match '^\d+$') {
            $taskIndex = [int]$num
            if ($taskIndex -ge 1 -and $taskIndex -le $AvailableTasks.Count) {
                $selectedTasks += $taskIndex
            }
        }
    }

    return $selectedTasks | Sort-Object | Get-Unique
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
        [hashtable]$Results,

        [Parameter()]
        [switch]$ShowDetails
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

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Show-MainMenu',
    'Show-TaskSelectionMenu', 
    'Show-ConfirmationDialog',
    'Show-Progress',
    'Show-ResultSummary'
)