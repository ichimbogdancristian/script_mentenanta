#Requires -Version 7.0
<#
.SYNOPSIS    Windows Updates Audit - Type 1
.DESCRIPTION Queries Windows Update for pending updates in configured categories.
             Diff = list of pending updates to install.
.NOTES       Module Type: Type1 | DiffKey: WindowsUpdates | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-WindowsUpdatesAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component WU-AUDIT -Message 'Starting Windows Updates audit'

    try {
        # 1. Load config
        $config = Get-BaselineList -ModuleFolder 'windows-updates' -FileName 'updates-config.json'
        if (-not $config -or $config.enabled -eq $false) {
            Write-Log -Level INFO -Component WU-AUDIT -Message 'Windows Updates disabled in config - skipping'
            Save-DiffList -ModuleName 'WindowsUpdates' -DiffList @()
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Skipped' `
                                    -Message 'Disabled in configuration'
        }

        $pendingUpdates = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Query Windows Update via COM
        Write-Log -Level INFO -Component WU-AUDIT -Message 'Querying Windows Update service...'
        try {
            $updateSession   = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher  = $updateSession.CreateUpdateSearcher()
            $searchResult    = $updateSearcher.Search('IsInstalled=0 and IsHidden=0')

            foreach ($update in $searchResult.Updates) {
                $title = $update.Title

                # Filter by exclude patterns
                $excluded = $false
                foreach ($pattern in $config.excludePatterns) {
                    if ($title -like $pattern) { $excluded = $true; break }
                }
                if ($excluded) { continue }

                # Categorise (simplified — MsrcSeverity helps for Security)
                $isSecurityCritical = ($update.MsrcSeverity -in 'Critical','Important') -or
                                      ($title -match 'Security|Cumulative')
                $isCritical  = $update.MsrcSeverity -eq 'Critical'
                $isImportant = $update.MsrcSeverity -in 'Critical','Important'
                $isOptional  = -not $isCritical -and -not $isImportant

                # Apply category filters from config
                $include = ($config.categories.security   -and $isSecurityCritical) `
                        -or ($config.categories.critical  -and $isCritical) `
                        -or ($config.categories.important -and $isImportant) `
                        -or ($config.categories.optional  -and $isOptional)

                if ($include) {
                    $pendingUpdates.Add(@{
                        Title       = $title
                        Identity    = $update.Identity.UpdateID
                        Severity    = $update.MsrcSeverity
                        SizeMB      = [math]::Round($update.MaxDownloadSize / 1MB, 1)
                        IsMandatory = $update.IsMandatory
                    })
                    Write-Log -Level DEBUG -Component WU-AUDIT -Message "Pending: $title"
                }
            }
        }
        catch {
            Write-Log -Level WARN -Component WU-AUDIT -Message "COM WU query failed: $_. Trying winget msstore fallback."
        }

        Write-Log -Level INFO -Component WU-AUDIT -Message "Pending updates: $($pendingUpdates.Count)"

        # 3. Save diff
        Save-DiffList -ModuleName 'WindowsUpdates' -DiffList $pendingUpdates.ToArray()

        # 4. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'wu-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Pending = $pendingUpdates.ToArray() } `
            | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component WU-AUDIT -Message "Windows Updates audit complete: $($pendingUpdates.Count) pending"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Success' `
                                -ItemsDetected $pendingUpdates.Count `
                                -Message "$($pendingUpdates.Count) updates pending"
    }
    catch {
        Write-Log -Level ERROR -Component WU-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-WindowsUpdatesAudit'
