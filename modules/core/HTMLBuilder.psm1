#Requires -Version 7.0

<#
.SYNOPSIS
    HTML Component Library for Report Generation (Phase 2)

.DESCRIPTION
    Provides reusable HTML components for building maintenance reports.
    Eliminates code duplication and ensures consistent styling across all reports.

    Architecture Context:
    - Module Type: Core Infrastructure
    - Version: 1.0.0 (Phase 2 - HTML Component Library)
    - Dependencies: CoreInfrastructure.psm1

.MODULE ARCHITECTURE
    Purpose:
        Centralized HTML generation with reusable components
        Reduces ReportGenerator complexity by ~1,000 lines

    Components:
        Core (8):
            • New-HtmlCard - Dashboard and metric cards
            • New-HtmlTable - Data tables with sorting support
            • New-HtmlSection - Content sections with headers
            • New-HtmlStatusBadge - Status indicator badges
            • New-HtmlDetailItem - Detail list items
            • New-HtmlLogEntry - Log entry display
            • New-HtmlMetric - Metric displays
            • New-HtmlIcon - Icon elements

        Composite (4):
            • New-DashboardCardGrid - 4-card executive summary
            • New-ModuleDetailsCard - Complete module result card
            • New-ExecutionLogTable - Operation log table
            • New-ErrorAnalysisSection - Error categorization

        Utilities (5):
            • Get-StatusClass - Status → CSS class mapping
            • Format-Duration - Seconds → readable duration
            • Format-FileSize - Bytes → KB/MB/GB
            • Escape-HtmlContent - HTML sanitization
            • Get-LevelIcon - Log level → emoji icon

    Export Pattern:
        Export-ModuleMember -Function @(
            'New-Html*',
            'Get-StatusClass',
            'Get-LevelIcon',
            'Format-Duration',
            'Format-FileSize',
            'Escape-HtmlContent'
        )

    Used By:
        - ReportGenerator.psm1 - Delegates all HTML generation to HTMLBuilder

.NOTES
    Module Type: Core Infrastructure (Phase 2)
    Architecture: v3.1.0 - Phase 2 HTML Component Library
    Version: 1.0.0
    Author: Bogdan Ichim

    Design Patterns:
    - Component-based rendering
    - Consistent styling and structure
    - Reusable building blocks
    - HTML sanitization and security
#>

# Import CoreInfrastructure for logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global
    Write-Verbose "HTMLBuilder: CoreInfrastructure imported"
}
else {
    Write-Warning "HTMLBuilder: CoreInfrastructure not found - logging may be limited"
}

#region Core Components

<#
.SYNOPSIS
    Creates a styled card component with title, value, description, and icon

.DESCRIPTION
    Generates HTML for dashboard cards, metric cards, and status cards.
    Supports glassmorphism styling and status-based color schemes.

.PARAMETER Title
    Card title/heading

.PARAMETER Value
    Primary value to display (e.g., score, count, percentage)

.PARAMETER Description
    Descriptive text below the value

.PARAMETER Icon
    Emoji or icon to display

.PARAMETER StatusClass
    CSS class for status-based styling (success, warning, error, info)

.PARAMETER CssClass
    Additional CSS classes to apply

.OUTPUTS
    [string] HTML card component

.EXAMPLE
    New-HtmlCard -Title 'System Health' -Value '95%' -Description 'Overall health score' -Icon '🏥' -StatusClass 'success'

    Creates a success-themed card with health metrics
#>
function New-HtmlCard {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Value = '',

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [string]$Icon = '',

        [Parameter()]
        [ValidateSet('success', 'warning', 'error', 'info', '')]
        [string]$StatusClass = '',

        [Parameter()]
        [string]$CssClass = 'card'
    )

    $statusClassStr = if ($StatusClass) { "status-$StatusClass" } else { '' }
    $fullClass = "$CssClass $statusClassStr".Trim()

    $iconHtml = if ($Icon) { "<div class='card-icon'>$Icon</div>" } else { '' }
    $valueHtml = if ($Value) { "<div class='card-value'>$Value</div>" } else { '' }
    $descHtml = if ($Description) { "<p class='card-description'>$Description</p>" } else { '' }

    return @"
<div class="$fullClass">
    <div class="card-header">
        $iconHtml
        <h3 class="card-title">$Title</h3>
    </div>
    <div class="card-content">
        $valueHtml
        $descHtml
    </div>
</div>
"@
}

<#
.SYNOPSIS
    Creates a data table with headers and rows

.DESCRIPTION
    Generates HTML table with optional sorting, striping, and hover effects.
    Supports dynamic row generation from PSCustomObject arrays.

.PARAMETER Headers
    Array of column headers

.PARAMETER Rows
    Array of data rows (PSCustomObject or Hashtable)

.PARAMETER CssClass
    CSS class for the table (default: data-table)

.PARAMETER Sortable
    Add sortable attributes to headers

.PARAMETER Striped
    Apply striped row styling

.PARAMETER Hoverable
    Enable hover effects on rows

.OUTPUTS
    [string] HTML table component

.EXAMPLE
    $rows = @(
        [PSCustomObject]@{ Module = 'Bloatware'; Status = 'Success'; Duration = '5.2s' }
        [PSCustomObject]@{ Module = 'Updates'; Status = 'Warning'; Duration = '120.5s' }
    )
    New-HtmlTable -Headers @('Module', 'Status', 'Duration') -Rows $rows -Sortable -Striped

    Creates sortable striped table with 3 columns and 2 rows
#>
function New-HtmlTable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Headers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSObject[]]$Rows,

        [Parameter()]
        [string]$CssClass = 'data-table',

        [Parameter()]
        [switch]$Sortable,

        [Parameter()]
        [switch]$Striped,

        [Parameter()]
        [switch]$Hoverable
    )

    # Build CSS classes
    $tableClasses = @($CssClass)
    if ($Sortable) { $tableClasses += 'sortable' }
    if ($Striped) { $tableClasses += 'striped' }
    if ($Hoverable) { $tableClasses += 'hoverable' }
    $tableClassStr = $tableClasses -join ' '

    # Build headers
    $headerHtml = @()
    foreach ($header in $Headers) {
        $sortableAttr = if ($Sortable) { ' data-sortable="true"' } else { '' }
        $headerHtml += "            <th$sortableAttr>$header</th>"
    }

    # Build rows
    $rowsHtml = @()
    foreach ($row in $Rows) {
        $cells = @()
        foreach ($header in $Headers) {
            $value = if ($row.$header) { $row.$header } else { '' }
            $cells += "            <td>$value</td>"
        }
        $rowsHtml += "        <tr>`n$($cells -join "`n")`n        </tr>"
    }

    return @"
<table class="$tableClassStr">
    <thead>
        <tr>
$($headerHtml -join "`n")
        </tr>
    </thead>
    <tbody>
$($rowsHtml -join "`n")
    </tbody>
</table>
"@
}

<#
.SYNOPSIS
    Creates a content section with header and body

.DESCRIPTION
    Generates HTML section with optional icon, collapsible functionality, and custom ID.
    Used for organizing report content into logical sections.

.PARAMETER Title
    Section title/heading

.PARAMETER Content
    Section body content (can contain HTML)

.PARAMETER Icon
    Emoji or icon for section header

.PARAMETER Collapsible
    Make section collapsible with toggle button

.PARAMETER Id
    HTML id attribute for the section

.OUTPUTS
    [string] HTML section component

.EXAMPLE
    $content = New-HtmlTable -Headers @('Name', 'Status') -Rows $data
    New-HtmlSection -Title 'Execution Summary' -Content $content -Icon '📊' -Collapsible -Id 'summary'

    Creates collapsible section with embedded table
#>
function New-HtmlSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter()]
        [string]$Icon = '',

        [Parameter()]
        [switch]$Collapsible,

        [Parameter()]
        [string]$Id = ''
    )

    $idAttr = if ($Id) { " id='$Id'" } else { '' }
    $collapsibleClass = if ($Collapsible) { ' collapsible' } else { '' }
    $iconHtml = if ($Icon) { "<span class='section-icon'>$Icon</span> " } else { '' }
    $toggleBtn = if ($Collapsible) { "<button class='toggle-btn' aria-expanded='true'>▼</button>" } else { '' }

    return @"
<section class="content-section$collapsibleClass"$idAttr>
    <div class="section-header">
        <h2 class="section-title">$iconHtml$Title</h2>
        $toggleBtn
    </div>
    <div class="section-body">
$Content
    </div>
</section>
"@
}

<#
.SYNOPSIS
    Creates a status indicator badge

.DESCRIPTION
    Generates styled badge for displaying status (success, warning, error, info).
    Supports different badge styles (pill, square, rounded).

.PARAMETER Status
    Status value (determines CSS class)

.PARAMETER Text
    Text to display in badge (defaults to Status if not provided)

.PARAMETER Style
    Badge style: pill (default), square, or rounded

.OUTPUTS
    [string] HTML status badge

.EXAMPLE
    New-HtmlStatusBadge -Status 'success' -Text 'Completed'

    Creates green success badge with "Completed" text

.EXAMPLE
    New-HtmlStatusBadge -Status 'error' -Style 'square'

    Creates red square-styled badge with "error" text
#>
function New-HtmlStatusBadge {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [string]$Text = '',

        [Parameter()]
        [ValidateSet('pill', 'square', 'rounded')]
        [string]$Style = 'pill'
    )

    $displayText = if ($Text) { $Text } else { $Status }
    $cssClass = Get-StatusClass -Status $Status
    $styleClass = if ($Style -ne 'pill') { " badge-$Style" } else { '' }

    return "<span class='status-badge $cssClass$styleClass'>$displayText</span>"
}

<#
.SYNOPSIS
    Creates a detail list item with icon, name, description, and status

.DESCRIPTION
    Generates HTML for detail list items showing detected/processed items.
    Used in module cards for displaying operation results.

.PARAMETER Name
    Item name (primary text)

.PARAMETER Description
    Item description or additional info

.PARAMETER Icon
    Emoji or icon (default: 📄)

.PARAMETER Status
    Item status for badge display

.PARAMETER Metadata
    Additional metadata to display (hashtable)

.OUTPUTS
    [string] HTML detail item component

.EXAMPLE
    New-HtmlDetailItem -Name 'Candy Crush' -Description 'Pre-installed bloatware' -Icon '🗑️' -Status 'Removed' -Metadata @{ Size = '150MB'; Location = 'C:\Program Files\' }

    Creates detail item with metadata display
#>
function New-HtmlDetailItem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [string]$Icon = '📄',

        [Parameter()]
        [string]$Status = '',

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    $descHtml = if ($Description) { "<div class='detail-item-description'>$Description</div>" } else { '' }

    $metadataHtml = @()
    foreach ($key in $Metadata.Keys) {
        $metadataHtml += "$key`: $($Metadata[$key])"
    }
    $metaDisplay = if ($metadataHtml.Count -gt 0) {
        "<div class='detail-item-metadata'>$($metadataHtml -join ' | ')</div>"
    } else { '' }

    $statusHtml = if ($Status) {
        $badge = New-HtmlStatusBadge -Status $Status
        "<div class='detail-item-status'>$badge</div>"
    } else { '' }

    return @"
<div class="detail-item">
    <div class="detail-item-icon">$Icon</div>
    <div class="detail-item-content">
        <div class="detail-item-name">$Name</div>
        $descHtml
        $metaDisplay
    </div>
    $statusHtml
</div>
"@
}

<#
.SYNOPSIS
    Creates a log entry with timestamp, level icon, and message

.DESCRIPTION
    Generates HTML for log entry display with automatic icon selection based on level.
    Used for displaying execution logs in module cards.

.PARAMETER Message
    Log message text

.PARAMETER Level
    Log level (success, info, warning, error, debug)

.PARAMETER Timestamp
    Timestamp for the log entry (defaults to current time)

.PARAMETER Component
    Component/module name that generated the log

.OUTPUTS
    [string] HTML log entry component

.EXAMPLE
    New-HtmlLogEntry -Message 'Bloatware removal completed' -Level 'success' -Timestamp (Get-Date) -Component 'BloatwareRemoval'

    Creates success-level log entry with timestamp
#>
function New-HtmlLogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('success', 'info', 'warning', 'error', 'debug')]
        [string]$Level = 'info',

        [Parameter()]
        [datetime]$Timestamp = (Get-Date),

        [Parameter()]
        [string]$Component = ''
    )

    $timestampStr = $Timestamp.ToString('HH:mm:ss')
    $icon = Get-LevelIcon -Level $Level
    $componentHtml = if ($Component) { "<span class='log-component'>[$Component]</span> " } else { '' }

    return @"
<div class="log-entry $Level">
    <div class="log-timestamp">$timestampStr</div>
    <div class="log-level-icon">$icon</div>
    <div class="log-message">$componentHtml$Message</div>
</div>
"@
}

<#
.SYNOPSIS
    Creates a metric display with label, value, and optional trend indicator

.DESCRIPTION
    Generates HTML for displaying key metrics with units and trend arrows.
    Used in dashboards and summary sections.

.PARAMETER Label
    Metric label/name

.PARAMETER Value
    Metric value

.PARAMETER Unit
    Unit of measurement (optional)

.PARAMETER Icon
    Emoji or icon for the metric

.PARAMETER TrendIndicator
    Trend arrow: ↑ (up), ↓ (down), → (neutral)

.OUTPUTS
    [string] HTML metric component

.EXAMPLE
    New-HtmlMetric -Label 'CPU Usage' -Value '45' -Unit '%' -Icon '🖥️' -TrendIndicator '↓'

    Creates metric display showing CPU usage trending down
#>
function New-HtmlMetric {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter()]
        [string]$Unit = '',

        [Parameter()]
        [string]$Icon = '',

        [Parameter()]
        [ValidateSet('↑', '↓', '→', '')]
        [string]$TrendIndicator = ''
    )

    $iconHtml = if ($Icon) { "<div class='metric-icon'>$Icon</div>" } else { '' }
    $unitHtml = if ($Unit) { "<span class='metric-unit'>$Unit</span>" } else { '' }
    $trendHtml = if ($TrendIndicator) {
        $trendClass = switch ($TrendIndicator) {
            '↑' { 'trend-up' }
            '↓' { 'trend-down' }
            '→' { 'trend-neutral' }
        }
        "<span class='metric-trend $trendClass'>$TrendIndicator</span>"
    } else { '' }

    return @"
<div class="metric-display">
    $iconHtml
    <div class="metric-content">
        <div class="metric-label">$Label</div>
        <div class="metric-value">$Value$unitHtml $trendHtml</div>
    </div>
</div>
"@
}

<#
.SYNOPSIS
    Creates an icon element

.DESCRIPTION
    Generates HTML for icon display with size and color options.
    Supports emoji icons and font-based icons.

.PARAMETER Icon
    Icon character (emoji or font icon class)

.PARAMETER Size
    Icon size: sm, md (default), lg, xl

.PARAMETER Color
    CSS color value or variable

.OUTPUTS
    [string] HTML icon element

.EXAMPLE
    New-HtmlIcon -Icon '🔒' -Size 'lg' -Color 'var(--success)'

    Creates large green lock icon
#>
function New-HtmlIcon {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Icon,

        [Parameter()]
        [ValidateSet('sm', 'md', 'lg', 'xl')]
        [string]$Size = 'md',

        [Parameter()]
        [string]$Color = ''
    )

    $style = if ($Color) { " style='color: $Color;'" } else { '' }

    return "<span class='icon icon-$Size'$style>$Icon</span>"
}

#endregion

#region Utility Functions

<#
.SYNOPSIS
    Maps status strings to CSS classes

.DESCRIPTION
    Converts various status values to standardized CSS classes.
    Handles common status variations (success, completed, removed, etc.)

.PARAMETER Status
    Status string to convert

.OUTPUTS
    [string] CSS class name

.EXAMPLE
    Get-StatusClass -Status 'Success'
    Returns: 'success'

    Get-StatusClass -Status 'Failed'
    Returns: 'error'
#>
function Get-StatusClass {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Status
    )

    $statusLower = $Status.ToLower()

    return switch -Regex ($statusLower) {
        '^(success|completed?|removed?|installed?|passed?|ok)$' { 'success' }
        '^(warning|skipped?|pending|partial)$' { 'warning' }
        '^(error|failed?|critical|blocked)$' { 'error' }
        '^(info|running|processing)$' { 'info' }
        default { 'info' }
    }
}

<#
.SYNOPSIS
    Formats seconds to readable duration string

.DESCRIPTION
    Converts duration in seconds to human-readable format:
    - < 60s: "X.Xs"
    - < 3600s: "Xm Ys"
    - >= 3600s: "Xh Ym"

.PARAMETER Seconds
    Duration in seconds

.OUTPUTS
    [string] Formatted duration

.EXAMPLE
    Format-Duration -Seconds 5.2
    Returns: "5.2s"

    Format-Duration -Seconds 125
    Returns: "2m 5s"

    Format-Duration -Seconds 3665
    Returns: "1h 1m"
#>
function Format-Duration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Seconds
    )

    if ($Seconds -lt 60) {
        return "$([Math]::Round($Seconds, 1))s"
    }
    elseif ($Seconds -lt 3600) {
        $minutes = [Math]::Floor($Seconds / 60)
        $secs = [Math]::Round($Seconds % 60)
        return "${minutes}m ${secs}s"
    }
    else {
        $hours = [Math]::Floor($Seconds / 3600)
        $minutes = [Math]::Floor(($Seconds % 3600) / 60)
        return "${hours}h ${minutes}m"
    }
}

<#
.SYNOPSIS
    Formats bytes to readable file size

.DESCRIPTION
    Converts bytes to appropriate unit (KB, MB, GB, TB) with 2 decimal places.

.PARAMETER Bytes
    Size in bytes

.OUTPUTS
    [string] Formatted file size

.EXAMPLE
    Format-FileSize -Bytes 1024
    Returns: "1.00 KB"

    Format-FileSize -Bytes 1572864
    Returns: "1.50 MB"
#>
function Format-FileSize {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $unitIndex = 0
    $size = [double]$Bytes

    while ($size -ge 1024 -and $unitIndex -lt ($units.Length - 1)) {
        $size /= 1024
        $unitIndex++
    }

    return "$([Math]::Round($size, 2)) $($units[$unitIndex])"
}

<#
.SYNOPSIS
    HTML-escapes content for safe display

.DESCRIPTION
    Escapes HTML special characters to prevent injection and rendering issues.
    Uses .NET WebUtility for reliable escaping.

.PARAMETER Content
    Content to escape

.OUTPUTS
    [string] HTML-escaped content

.EXAMPLE
    Escape-HtmlContent -Content '<script>alert("XSS")</script>'
    Returns: '&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;'
#>
function Escape-HtmlContent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    return [System.Net.WebUtility]::HtmlEncode($Content)
}

<#
.SYNOPSIS
    Returns emoji icon for log level

.DESCRIPTION
    Maps log levels to appropriate emoji icons for visual identification.

.PARAMETER Level
    Log level (success, info, warning, error, debug)

.OUTPUTS
    [string] Emoji icon

.EXAMPLE
    Get-LevelIcon -Level 'success'
    Returns: '✓'

    Get-LevelIcon -Level 'error'
    Returns: '✗'
#>
function Get-LevelIcon {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Level
    )

    return switch ($Level.ToLower()) {
        'success' { '✓' }
        'info' { 'ℹ' }
        'warning' { '⚠' }
        'error' { '✗' }
        'debug' { '🔍' }
        default { '•' }
    }
}

#endregion

#region Composite Components

<#
.SYNOPSIS
    Creates a 4-card dashboard grid with system metrics

.DESCRIPTION
    Generates executive dashboard with 4 metric cards (health, security, success rate, tasks).
    Uses New-HtmlCard for consistent styling.

.PARAMETER Metrics
    Hashtable containing metric values:
    - HealthScore: Overall system health (0-100)
    - SecurityScore: Security score (0-100)
    - SuccessRate: Task success rate percentage
    - TotalTasks: Total number of tasks executed

.OUTPUTS
    [string] HTML dashboard grid

.EXAMPLE
    $metrics = @{
        HealthScore = 95
        SecurityScore = 88
        SuccessRate = 92
        TotalTasks = 12
    }
    New-DashboardCardGrid -Metrics $metrics

    Creates 4-card dashboard grid with provided metrics
#>
function New-DashboardCardGrid {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metrics
    )

    Write-Verbose "Building dashboard card grid"

    # Extract metrics with defaults
    $healthScore = $Metrics.HealthScore ?? 0
    $securityScore = $Metrics.SecurityScore ?? 0
    $successRate = $Metrics.SuccessRate ?? 0
    $totalTasks = $Metrics.TotalTasks ?? 0

    # Determine status classes based on scores
    $healthClass = if ($healthScore -ge 85) { 'success' } elseif ($healthScore -ge 70) { 'warning' } else { 'error' }
    $securityClass = if ($securityScore -ge 85) { 'success' } elseif ($securityScore -ge 70) { 'warning' } else { 'error' }
    $successClass = if ($successRate -ge 90) { 'success' } elseif ($successRate -ge 75) { 'warning' } else { 'error' }

    # Status text
    $healthText = if ($healthScore -ge 85) { 'Excellent' } elseif ($healthScore -ge 70) { 'Good' } else { 'Needs Attention' }
    $securityText = if ($securityScore -ge 85) { 'Secure' } elseif ($securityScore -ge 70) { 'Fair' } else { 'At Risk' }

    # Build cards using New-HtmlCard
    $card1 = New-HtmlCard -Title 'System Health' -Value "${healthScore}%" -Description $healthText -Icon '🏥' -StatusClass $healthClass -CssClass 'card status-card'
    $card2 = New-HtmlCard -Title 'Security Score' -Value "${securityScore}%" -Description $securityText -Icon '🔐' -StatusClass $securityClass -CssClass 'card status-card'
    $card3 = New-HtmlCard -Title 'Success Rate' -Value "${successRate}%" -Description 'Tasks completed successfully' -Icon '✓' -StatusClass $successClass -CssClass 'card status-card'
    $card4 = New-HtmlCard -Title 'Total Tasks' -Value "$totalTasks" -Description 'Maintenance tasks executed' -Icon '📋' -CssClass 'card status-card'

    return @"
<section class="grid grid-4" id="summaryCards">
$card1
$card2
$card3
$card4
</section>
"@
}

<#
.SYNOPSIS
    Creates a complete module result card with details and logs

.DESCRIPTION
    Generates comprehensive module card showing execution results, detected/processed items, and logs.
    Uses multiple core components for consistent structure.

.PARAMETER ModuleResult
    PSObject containing module execution results

.PARAMETER ShowLogs
    Include log entries in the card (default: true)

.PARAMETER MaxItems
    Maximum number of items to display (default: 10)

.OUTPUTS
    [string] HTML module details card

.EXAMPLE
    New-ModuleDetailsCard -ModuleResult $moduleResult -ShowLogs -MaxItems 10

    Creates full module card with up to 10 items and logs
#>
function New-ModuleDetailsCard {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSObject]$ModuleResult,

        [Parameter()]
        [switch]$ShowLogs = $true,

        [Parameter()]
        [int]$MaxItems = 10
    )

    Write-Verbose "Building module details card for $($ModuleResult.ModuleName)"

    # Module metadata
    $moduleInfo = @{
        'BloatwareRemoval' = @{ Icon = '🗑️'; Description = 'Removes unnecessary pre-installed software' }
        'EssentialApps' = @{ Icon = '📦'; Description = 'Installs and manages essential applications' }
        'SystemOptimization' = @{ Icon = '⚡'; Description = 'Optimizes system performance' }
        'TelemetryDisable' = @{ Icon = '🔒'; Description = 'Disables telemetry and enhances privacy' }
        'WindowsUpdates' = @{ Icon = '🔄'; Description = 'Manages system updates' }
        'SecurityAudit' = @{ Icon = '🛡️'; Description = 'Security assessment and recommendations' }
        'SystemInventory' = @{ Icon = '📊'; Description = 'System hardware and software inventory' }
        'AppUpgrade' = @{ Icon = '⬆️'; Description = 'Updates applications to latest versions' }
        'SecurityEnhancement' = @{ Icon = '🔐'; Description = 'Applies security configurations' }
    }

    $moduleName = $ModuleResult.ModuleName
    $info = $moduleInfo[$moduleName] ?? @{ Icon = '⚙️'; Description = 'Module execution results' }

    # Extract metrics
    $totalOps = [int]($ModuleResult.Metrics.ItemsProcessed ?? $ModuleResult.ItemsProcessed ?? 0)
    $successOps = [int]($ModuleResult.Metrics.ItemsSuccessful ?? $ModuleResult.SuccessfulOperations ?? 0)
    $durationSec = [double]($ModuleResult.Metrics.DurationSeconds ?? $ModuleResult.DurationSeconds ?? 0)
    $status = $ModuleResult.Status ?? 'Completed'

    # Build detail items for detected/processed items
    $detailsHtml = @()

    if ($ModuleResult.DetectedItems -and $ModuleResult.DetectedItems.Count -gt 0) {
        $detailsHtml += "<div class='detail-section'>"
        $detailsHtml += "<h4 class='detail-section-title'><span>🔍</span> Detected Items</h4>"
        $detailsHtml += "<div class='detail-list'>"

        foreach ($item in $ModuleResult.DetectedItems | Select-Object -First $MaxItems) {
            $itemName = if ($item.Name) { $item.Name } elseif ($item.DisplayName) { $item.DisplayName } else { $item.ToString() }
            $itemStatus = if ($item.Status) { $item.Status } else { 'Detected' }
            $metadata = @{}
            if ($item.Version) { $metadata.Version = $item.Version }
            if ($item.Size) { $metadata.Size = $item.Size }

            $detailsHtml += New-HtmlDetailItem -Name $itemName -Icon '📄' -Status $itemStatus -Metadata $metadata
        }

        if ($ModuleResult.DetectedItems.Count -gt $MaxItems) {
            $remaining = $ModuleResult.DetectedItems.Count - $MaxItems
            $detailsHtml += "<div style='text-align: center; padding: 10px; color: var(--text-muted);'>+ $remaining more items...</div>"
        }

        $detailsHtml += "</div></div>"
    }

    # Build log entries if requested
    $logsHtml = ''
    if ($ShowLogs -and $ModuleResult.Logs -and $ModuleResult.Logs.Count -gt 0) {
        $logEntries = @()
        foreach ($log in $ModuleResult.Logs | Select-Object -First 20) {
            $level = if ($log.Level) { $log.Level.ToLower() } else { 'info' }
            $message = if ($log.Message) { $log.Message } else { $log.ToString() }
            $timestamp = if ($log.Timestamp) { [datetime]::Parse($log.Timestamp) } else { Get-Date }

            $logEntries += New-HtmlLogEntry -Message $message -Level $level -Timestamp $timestamp
        }

        $logsHtml = @"
<div class='log-section'>
    <h4 class='log-title'>📝 Recent Activity</h4>
    <div class='log-list'>
$($logEntries -join "`n")
    </div>
</div>
"@
    }

    # Build complete card
    $badge = New-HtmlStatusBadge -Status $status
    $durationFormatted = Format-Duration -Seconds $durationSec

    return @"
<div class='card module-card $(Get-StatusClass -Status $status) fade-in'>
    <div class='card-header'>
        <div class='card-icon'>$($info.Icon)</div>
        <h3 class='card-title'>$moduleName</h3>
        <div class='module-status'>$badge</div>
    </div>
    <div class='card-content'>
        <p class='module-description'>$($info.Description)</p>
        <div class='module-stats'>
            <div class='stat-item'><span class='stat-label'>Duration:</span> <span class='stat-value'>$durationFormatted</span></div>
            <div class='stat-item'><span class='stat-label'>Items Processed:</span> <span class='stat-value'>$totalOps</span></div>
            <div class='stat-item'><span class='stat-label'>Successful:</span> <span class='stat-value'>$successOps</span></div>
        </div>
$($detailsHtml -join "`n")
$logsHtml
    </div>
</div>
"@
}

<#
.SYNOPSIS
    Creates an execution log table with operation results

.DESCRIPTION
    Generates table showing module execution results with status badges.
    Uses New-HtmlTable and New-HtmlStatusBadge.

.PARAMETER Operations
    Array of operation results (PSCustomObject with Module, Status, Duration, Items properties)

.OUTPUTS
    [string] HTML execution log table

.EXAMPLE
    New-ExecutionLogTable -Operations $moduleResults

    Creates table with all module execution results
#>
function New-ExecutionLogTable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Operations
    )

    Write-Verbose "Building execution log table with $($Operations.Count) entries"

    # Transform operations to include formatted data
    $tableData = @()
    foreach ($op in $Operations) {
        $badge = New-HtmlStatusBadge -Status ($op.Status ?? 'Unknown')
        $duration = if ($op.Duration) { Format-Duration -Seconds $op.Duration } else { 'N/A' }

        $tableData += [PSCustomObject]@{
            Module = $op.Module ?? 'Unknown'
            Status = $badge
            Duration = $duration
            Items = $op.Items ?? 0
        }
    }

    return New-HtmlTable -Headers @('Module', 'Status', 'Duration', 'Items') -Rows $tableData -Sortable -Striped -Hoverable
}

<#
.SYNOPSIS
    Creates error categorization section (critical/error/warning)

.DESCRIPTION
    Generates comprehensive error analysis section with errors grouped by severity.
    Uses New-HtmlSection and New-HtmlDetailItem.

.PARAMETER AggregatedResults
    Hashtable containing module results with errors and warnings

.OUTPUTS
    [string] HTML error analysis section

.EXAMPLE
    New-ErrorAnalysisSection -AggregatedResults $results

    Creates error analysis with categorized errors
#>
function New-ErrorAnalysisSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults
    )

    Write-Verbose "Building error analysis section"

    # Categorize errors by severity
    $criticalErrors = @()
    $errors = @()
    $warnings = @()

    foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
        $moduleName = $moduleResult.ModuleName

        # Process errors
        if ($moduleResult.Errors -and $moduleResult.Errors.Count -gt 0) {
            foreach ($errorItem in $moduleResult.Errors) {
                $errorMessage = if ($errorItem.Message) { $errorItem.Message }
                                elseif ($errorItem -is [string]) { $errorItem }
                                else { $errorItem.ToString() }

                # Determine severity (simple heuristic)
                $severity = if ($errorMessage -match 'critical|fatal|system') { 'Critical' }
                           elseif ($errorMessage -match 'error|failed|exception') { 'Error' }
                           else { 'Warning' }

                $errorObj = @{
                    Module = $moduleName
                    Message = $errorMessage
                    Severity = $severity
                }

                switch ($severity) {
                    'Critical' { $criticalErrors += $errorObj }
                    'Error' { $errors += $errorObj }
                    'Warning' { $warnings += $errorObj }
                }
            }
        }

        # Process warnings
        if ($moduleResult.Warnings -and $moduleResult.Warnings.Count -gt 0) {
            foreach ($warning in $moduleResult.Warnings) {
                $warningMessage = if ($warning.Message) { $warning.Message }
                                 elseif ($warning -is [string]) { $warning }
                                 else { $warning.ToString() }

                $warnings += @{
                    Module = $moduleName
                    Message = $warningMessage
                    Severity = 'Warning'
                }
            }
        }
    }

    # Build error sections
    $sectionsHtml = @()

    if ($criticalErrors.Count -gt 0) {
        $criticalItems = @()
        foreach ($item in $criticalErrors) {
            $criticalItems += New-HtmlDetailItem -Name "[$($item.Module)] $($item.Message)" -Icon '🔴' -Status 'Critical'
        }
        $sectionsHtml += @"
<div class='error-category critical'>
    <div class='category-header'>
        <span class='category-icon'>🔴</span>
        <span class='category-title'>Critical Issues ($($criticalErrors.Count))</span>
    </div>
    <div class='category-content'>
$($criticalItems -join "`n")
    </div>
</div>
"@
    }

    if ($errors.Count -gt 0) {
        $errorItems = @()
        foreach ($item in $errors) {
            $errorItems += New-HtmlDetailItem -Name "[$($item.Module)] $($item.Message)" -Icon '❌' -Status 'Error'
        }
        $sectionsHtml += @"
<div class='error-category error'>
    <div class='category-header'>
        <span class='category-icon'>❌</span>
        <span class='category-title'>Errors ($($errors.Count))</span>
    </div>
    <div class='category-content'>
$($errorItems -join "`n")
    </div>
</div>
"@
    }

    if ($warnings.Count -gt 0) {
        $warningItems = @()
        foreach ($item in $warnings | Select-Object -First 10) {
            $warningItems += New-HtmlDetailItem -Name "[$($item.Module)] $($item.Message)" -Icon '⚠️' -Status 'Warning'
        }
        if ($warnings.Count -gt 10) {
            $warningItems += "<div style='text-align: center; padding: 10px;'>+ $($warnings.Count - 10) more warnings...</div>"
        }
        $sectionsHtml += @"
<div class='error-category warning'>
    <div class='category-header'>
        <span class='category-icon'>⚠️</span>
        <span class='category-title'>Warnings ($($warnings.Count))</span>
    </div>
    <div class='category-content'>
$($warningItems -join "`n")
    </div>
</div>
"@
    }

    $content = if ($sectionsHtml.Count -gt 0) {
        $sectionsHtml -join "`n"
    } else {
        "<div style='text-align: center; padding: 20px; color: var(--success);'>✓ No errors or warnings detected</div>"
    }

    return New-HtmlSection -Title 'Error Analysis' -Content $content -Icon '🔍' -Collapsible -Id 'error-analysis'
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    # Core Components
    'New-HtmlCard',
    'New-HtmlTable',
    'New-HtmlSection',
    'New-HtmlStatusBadge',
    'New-HtmlDetailItem',
    'New-HtmlLogEntry',
    'New-HtmlMetric',
    'New-HtmlIcon',
    # Composite Components
    'New-DashboardCardGrid',
    'New-ModuleDetailsCard',
    'New-ExecutionLogTable',
    'New-ErrorAnalysisSection',
    # Utilities
    'Get-StatusClass',
    'Format-Duration',
    'Format-FileSize',
    'Escape-HtmlContent',
    'Get-LevelIcon'
)

Write-Verbose "HTMLBuilder module loaded successfully (17 functions exported)"

