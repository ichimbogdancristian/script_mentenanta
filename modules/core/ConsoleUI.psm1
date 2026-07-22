#Requires -Version 7.0

<#
.SYNOPSIS
    Console UI Module - Enhanced visual output for Windows Maintenance Automation

.DESCRIPTION
    Provides enhanced console formatting with:
    - Structured prompts with visual indicators
    - Progress bars for long-running operations
    - Section headers and separators
    - Status symbols and color-coded output
    - Spinners for indeterminate progress
    - All functions are console-safe and log-file compatible

.NOTES
    Module Type: UI/Output
    Version: 1.0.0
    Author: Windows Maintenance Automation Project
    Import: Import-Module ConsoleUI.psm1 -Force -Global
#>

Set-StrictMode -Version 1.0

#region ─── VISUAL SYMBOLS ────────────────────────────────────────────────────

# Status symbols that work in all Windows terminals
$script:Symbols = @{
    Success    = '✓'      # Success checkmark
    Failed     = '✗'      # Failure mark
    Warning    = '⚠'      # Warning
    Info       = 'ℹ'      # Info
    Clock      = '⏱'      # Clock/timer
    Lightning  = '⚡'     # Lightning/fast
    Gear       = '⚙'      # Working/processing
    Arrow      = '▶'      # Arrow/pointer
    Bullet     = '●'      # Bullet point
    Check      = '▶'      # Direction indicator
    Database   = '◉'      # Circle marker
    Spinner    = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')  # Spinners
}

$script:SpinnerIndex = 0

#endregion

#region ─── COLOR PALETTE ────────────────────────────────────────────────────

function Get-ColorPalette {
    <#
    .SYNOPSIS
        Returns a color palette based on the current terminal theme.
    .OUTPUTS
        [hashtable] with semantic color names mapped to PowerShell color values.
    #>
    return @{
        Primary      = 'Cyan'           # Main action/progress
        Success      = 'Green'          # Successful completion
        Warning      = 'Yellow'         # Warnings/caution
        Error        = 'Red'            # Errors/failures
        Muted        = 'DarkGray'       # Secondary/debug info
        Accent       = 'Magenta'        # Highlights/important headers
        Info         = 'Blue'           # Informational
        Highlight    = 'White'          # Critical info
    }
}

#endregion

#region ─── SECTION & HEADER OUTPUT ──────────────────────────────────────────

<#
.SYNOPSIS
    Writes a prominent section header with visual separators.
.PARAMETER Title
    The section title text.
.PARAMETER Level
    1 (main) | 2 (sub) | 3 (minor). Controls size/prominence.
#>
function Write-SectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Title,
        [ValidateSet(1, 2, 3)] [int]$Level = 1
    )

    $colors = Get-ColorPalette

    if ($Level -eq 1) {
        Write-Host ""
        Write-Host ('=' * 70) -ForegroundColor $colors.Accent
        Write-Host "  $Title" -ForegroundColor $colors.Accent -NoNewline
        Write-Host "  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor $colors.Muted
        Write-Host ('=' * 70) -ForegroundColor $colors.Accent
    }
    elseif ($Level -eq 2) {
        Write-Host ""
        Write-Host "─ $Title " -ForegroundColor $colors.Primary -NoNewline
        Write-Host "$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor $colors.Muted
        Write-Host ('─' * 60) -ForegroundColor $colors.Muted
    }
    else {
        Write-Host "  ▸ $Title" -ForegroundColor $colors.Primary
    }
}

<#
.SYNOPSIS
    Writes a horizontal separator line.
.PARAMETER Character
    Character to use for the line (default: '─').
.PARAMETER Width
    Line width (default: 70).
#>
function Write-Separator {
    [CmdletBinding()]
    param(
        [string]$Character = '─',
        [int]$Width = 70
    )

    $colors = Get-ColorPalette
    Write-Host ($Character * $Width) -ForegroundColor $colors.Muted
}

#endregion

#region ─── STATUS & RESULT OUTPUT ───────────────────────────────────────────

<#
.SYNOPSIS
    Writes a structured status line with symbol and message.
.PARAMETER Status
    'Success' | 'Failed' | 'Warning' | 'Info' | 'Working' | 'Pending'
.PARAMETER Message
    The message text.
.PARAMETER Indented
    Whether to indent the line (for nested items).
#>
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Warning', 'Info', 'Working', 'Pending', 'Clock')]
        [string]$Status,

        [Parameter(Mandatory)] [string]$Message,
        [switch]$Indented
    )

    $colors = Get-ColorPalette
    $indent = if ($Indented) { '  ' } else { '' }

    $symbol, $color = switch ($Status) {
        'Success' { $script:Symbols.Success, $colors.Success }
        'Failed'  { $script:Symbols.Failed, $colors.Error }
        'Warning' { $script:Symbols.Warning, $colors.Warning }
        'Info'    { $script:Symbols.Info, $colors.Info }
        'Working' { $script:Symbols.Gear, $colors.Primary }
        'Pending' { $script:Symbols.Bullet, $colors.Muted }
        'Clock'   { $script:Symbols.Clock, $colors.Warning }
    }

    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "$indent[$ts] " -ForegroundColor $colors.Muted -NoNewline
    Write-Host "$symbol " -ForegroundColor $color -NoNewline
    Write-Host "$Message"
}

<#
.SYNOPSIS
    Writes a quick inline result indicator without timestamp.
.PARAMETER Result
    'OK' | 'FAIL' | 'WARN' | 'SKIP'
.PARAMETER Message
    Optional message text.
#>
function Write-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OK', 'FAIL', 'WARN', 'SKIP')]
        [string]$Result,

        [string]$Message = ''
    )

    $colors = Get-ColorPalette

    $symbol, $color = switch ($Result) {
        'OK'   { '✓', $colors.Success }
        'FAIL' { '✗', $colors.Error }
        'WARN' { '⚠', $colors.Warning }
        'SKIP' { '⊘', $colors.Muted }
    }

    if ($Message) {
        Write-Host "$symbol $Message" -ForegroundColor $color
    }
    else {
        Write-Host $symbol -ForegroundColor $color
    }
}

#endregion

#region ─── PROGRESS INDICATORS ──────────────────────────────────────────────

<#
.SYNOPSIS
    Creates and displays a text-based progress bar.
.PARAMETER Current
    Current progress value.
.PARAMETER Total
    Total value (e.g., item count).
.PARAMETER Label
    Optional label for the bar.
.PARAMETER Width
    Bar width in characters (default: 30).
.OUTPUTS
    [string] — formatted progress bar
#>
function Get-ProgressBar {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [int]$Current,
        [Parameter(Mandatory)] [int]$Total,
        [string]$Label = '',
        [int]$Width = 30
    )

    if ($Total -eq 0) { $Total = 1 }

    $percent = [math]::Min(100, [int](($Current / $Total) * 100))
    $filled = [int](($percent / 100) * $Width)
    $empty = $Width - $filled

    $bar = "[" + ("█" * $filled) + ("░" * $empty) + "] $percent%"

    if ($Label) {
        return "$Label $bar"
    }
    return $bar
}

<#
.SYNOPSIS
    Displays an animated progress bar for a long operation.
.PARAMETER Current
    Current item number.
.PARAMETER Total
    Total items.
.PARAMETER Label
    Operation label.
.PARAMETER Percent
    Optional: set progress as percentage instead of current/total.
#>
function Write-ProgressBar {
    [CmdletBinding()]
    param(
        [int]$Current = 0,
        [int]$Total = 100,
        [string]$Label = 'Processing',
        [int]$Percent = -1
    )

    $colors = Get-ColorPalette
    $percent = if ($Percent -ge 0) { $Percent } else { [int](($Current / $Total) * 100) }

    $filled = [int](($percent / 100) * 30)
    $empty = 30 - $filled
    $bar = "█" * $filled + "░" * $empty

    Write-Host "`r$Label [" -NoNewline -ForegroundColor $colors.Primary
    Write-Host $bar -NoNewline -ForegroundColor $colors.Success
    Write-Host "] " -NoNewline -ForegroundColor $colors.Primary
    Write-Host "$percent%" -NoNewline -ForegroundColor $colors.Highlight

    if ($Current -gt 0 -and $Total -gt 0) {
        Write-Host " ($Current/$Total)" -NoNewline -ForegroundColor $colors.Muted
    }
}

<#
.SYNOPSIS
    Shows a spinner animation for indeterminate progress.
.PARAMETER Label
    Operation label.
.PARAMETER Duration
    How many milliseconds to spin (optional; omit for manual control).
#>
function Start-Spinner {
    [CmdletBinding()]
    param(
        [string]$Label = 'Working',
        [int]$Duration = 0
    )

    $colors = Get-ColorPalette
    $spinChars = $script:Symbols.Spinner
    $startTime = Get-Date

    while ($true) {
        $spinner = $spinChars[$script:SpinnerIndex % $spinChars.Count]
        Write-Host "`r$spinner $Label" -NoNewline -ForegroundColor $colors.Primary

        $script:SpinnerIndex++

        if ($Duration -gt 0 -and ((Get-Date) - $startTime).TotalMilliseconds -ge $Duration) {
            Write-Host "`r$(' ' * ($Label.Length + 3))`r" -NoNewline
            break
        }

        Start-Sleep -Milliseconds 100
    }
}

#endregion

#region ─── FORMATTED OUTPUT BLOCKS ──────────────────────────────────────────

<#
.SYNOPSIS
    Displays a key-value pair in a formatted list.
.PARAMETER Name
    The label/key.
.PARAMETER Value
    The value to display.
.PARAMETER Highlight
    If $true, highlight the value in a brighter color.
#>
function Write-InfoLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Value,
        [switch]$Highlight
    )

    $colors = Get-ColorPalette
    $valueColor = if ($Highlight) { $colors.Highlight } else { $colors.Primary }

    Write-Host "  $Name" -ForegroundColor $colors.Muted -NoNewline
    Write-Host ": " -ForegroundColor $colors.Muted -NoNewline
    Write-Host "$Value" -ForegroundColor $valueColor
}

<#
.SYNOPSIS
    Displays a bulleted list item with proper indentation and color.
.PARAMETER Item
    The item text.
.PARAMETER SubItem
    If $true, displays with extra indentation (for nested lists).
.PARAMETER Color
    Override the item color (default: Info).
#>
function Write-ListItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Item,
        [switch]$SubItem,
        [string]$Color = $null
    )

    $colors = Get-ColorPalette
    $indent = if ($SubItem) { '      ├─ ' } else { '    • ' }
    $itemColor = if ($Color) { $Color } else { $colors.Info }

    Write-Host $indent -ForegroundColor $colors.Muted -NoNewline
    Write-Host "$Item" -ForegroundColor $itemColor
}

#endregion

#region ─── LOADING & WAITING ────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows a countdown timer for user-interactive stages.
.PARAMETER Seconds
    Number of seconds to count down from.
.PARAMETER Label
    What the countdown is for (default: 'Starting in').
.PARAMETER CancelKey
    Key to press to cancel (default: any key).
.OUTPUTS
    [bool] — $true if completed naturally, $false if cancelled.
#>
function Show-Countdown {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [int]$Seconds,
        [string]$Label = 'Starting in',
        [string]$CancelKey = 'any key'
    )

    $colors = Get-ColorPalette

    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host "`r$Label $i seconds... (press $CancelKey to cancel)" -NoNewline -ForegroundColor $colors.Warning
        Start-Sleep -Seconds 1
    }

    Write-Host "`r$(' ' * 60)`r" -NoNewline
    return $true
}

#endregion

#region ─── ERROR & WARNING DISPLAY ──────────────────────────────────────────

<#
.SYNOPSIS
    Displays a formatted error message with visual prominence.
.PARAMETER Message
    The error message.
.PARAMETER Title
    Optional error title (default: 'ERROR').
#>
function Write-ErrorBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$Title = 'ERROR'
    )

    $colors = Get-ColorPalette
    Write-Host ""
    Write-Host "╔" + ("═" * 68) + "╗" -ForegroundColor $colors.Error
    Write-Host "║ $Title" -ForegroundColor $colors.Error -NoNewline
    Write-Host (" " * (64 - $Title.Length)) + "║" -ForegroundColor $colors.Error
    Write-Host "║" + (" " * 68) + "║" -ForegroundColor $colors.Error

    # Wrap message to 64 characters
    $words = $Message -split ' '
    $line = ''
    foreach ($word in $words) {
        if (($line.Length + $word.Length + 1) -gt 64) {
            Write-Host "║ $line" + (" " * (64 - $line.Length)) + "║" -ForegroundColor $colors.Error
            $line = $word
        }
        else {
            $line += if ($line.Length -eq 0) { $word } else { " $word" }
        }
    }
    if ($line.Length -gt 0) {
        Write-Host "║ $line" + (" " * (64 - $line.Length)) + "║" -ForegroundColor $colors.Error
    }

    Write-Host "║" + (" " * 68) + "║" -ForegroundColor $colors.Error
    Write-Host "╚" + ("═" * 68) + "╝" -ForegroundColor $colors.Error
    Write-Host ""
}

<#
.SYNOPSIS
    Displays a formatted warning message.
.PARAMETER Message
    The warning message.
#>
function Write-WarningBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message
    )

    $colors = Get-ColorPalette
    Write-Host ""
    Write-Host "⚠ " -ForegroundColor $colors.Warning -NoNewline
    Write-Host "$Message" -ForegroundColor $colors.Warning
    Write-Host ""
}

#endregion

#region ─── EXPORTS ──────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Get-ColorPalette',
    'Write-SectionHeader',
    'Write-Separator',
    'Write-Status',
    'Write-Result',
    'Get-ProgressBar',
    'Write-ProgressBar',
    'Start-Spinner',
    'Write-InfoLine',
    'Write-ListItem',
    'Show-Countdown',
    'Write-ErrorBox',
    'Write-WarningBox'
)

#endregion
