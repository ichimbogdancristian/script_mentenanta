#Requires -Version 7.0
<#
.SYNOPSIS    Restore Point Audit - Type 1 (Consolidate & Cleanup audit)
.DESCRIPTION Audits current system restore points and identifies candidates for consolidation.
             Detects excessive restore points and recommends cleanup (keeping minimum 5 most recent).
             Creates a diff list indicating which restore points should be removed.
.NOTES       Module Type: Type1 | DiffKey: RestorePoint | Version: 1.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-RestorePointAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component RESTORE-AUDIT -Message 'Starting system restore point audit'

    try {
        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $restorePoints = @()
        $removeCount = 0

        # Get current restore points (use CIM since Get-ComputerRestorePoint is PS5.1 only)
        try {
            $restorePoints = @(Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
                Sort-Object -Property InstallDate -Descending |
                ForEach-Object {
                    [PSCustomObject]@{
                        SequenceNumber = $_.ID -replace '.*{|}', ''
                        Description    = $_.Description ?? 'System Restore Point'
                        CreationTime   = if ($_.InstallDate) { $_.InstallDate } else { [datetime]::Now }
                        EventType      = 'ShadowCopy'
                        RestorePointType = 'System'
                    }
                })
        }
        catch {
            Write-Log -Level WARN -Component RESTORE-AUDIT -Message "Could not query restore points: $_"
            return New-ModuleResult -ModuleName 'RestorePointAudit' -Status 'Failed' -Errors @("Restore points query failed: $_")
        }

        if ($restorePoints.Count -eq 0) {
            Write-Log -Level INFO -Component RESTORE-AUDIT -Message 'No restore points found'
            Save-DiffList -ModuleName 'RestorePoint' -DiffList $diff.ToArray()
            return New-ModuleResult -ModuleName 'RestorePointAudit' -Status 'Success' `
                -Message 'No restore points to manage'
        }

        Write-Log -Level INFO -Component RESTORE-AUDIT -Message "Current restore points: $($restorePoints.Count)"

        # Identify restore points to remove (keep at least 5 most recent)
        $minToKeep = 5
        if ($restorePoints.Count -gt $minToKeep) {
            $pointsToRemove = $restorePoints[$minToKeep..($restorePoints.Count - 1)]

            foreach ($point in $pointsToRemove) {
                $diff.Add(@{
                    Action           = 'remove'
                    SequenceNumber   = $point.SequenceNumber
                    Description      = $point.Description
                    CreationTime     = $point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                    EventType        = $point.EventType
                    RestorePointType = $point.RestorePointType
                })
                $removeCount++
                Write-Log -Level DEBUG -Component RESTORE-AUDIT -Message "Marked for removal: $($point.Description) (seq: $($point.SequenceNumber), created: $($point.CreationTime))"
            }
        }

        # Always create a new restore point (even if not removing others)
        $diff.Add(@{
            Action      = 'create'
            Description = "Maintenance: $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))"
            AllocationGB = 10
        })

        Write-Log -Level INFO -Component RESTORE-AUDIT -Message "Restore point audit: $($restorePoints.Count) current, $removeCount to remove, 1 to create"

        Save-DiffList -ModuleName 'RestorePoint' -DiffList $diff.ToArray()

        # Save audit report
        $auditData = @{
            Timestamp          = Get-Date -Format 'o'
            CurrentCount       = $restorePoints.Count
            MinimumToKeep      = $minToKeep
            ToRemove           = $removeCount
            ToCreate           = 1
            AllocationGB       = 10
            RestorePointsList  = $restorePoints | ForEach-Object {
                @{
                    SequenceNumber   = $_.SequenceNumber
                    Description      = $_.Description
                    CreationTime     = $_.CreationTime
                    EventType        = $_.EventType
                    RestorePointType = $_.RestorePointType
                }
            }
        }

        $reportPath = Get-TempPath -Category 'data' -FileName 'restore-point-audit.json'
        $auditData | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8 -Force

        $status = if ($removeCount -gt 0) { 'Warning' } else { 'Success' }
        $message = "Restore points: $($restorePoints.Count) current, $removeCount to remove, 1 to create"

        return New-ModuleResult -ModuleName 'RestorePointAudit' -Status $status -ModuleType 'Type1' `
            -ItemsDetected ($diff.Count) -Message $message `
            -ExtraData @{
                CurrentCount   = $restorePoints.Count
                ToRemove       = $removeCount
                ToCreate       = 1
            }
    }
    catch {
        Write-Log -Level ERROR -Component RESTORE-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'RestorePointAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-RestorePointAudit'
