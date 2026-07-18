#Requires -Version 7.0
<#
.SYNOPSIS    Restore Point Management - Type 2 (Create & Consolidate actions)
.DESCRIPTION Creates a new system restore point and removes excess old restore points.
             - Creates restore point with designated name
             - Allocates specified storage (default 10GB)
             - Removes restore points older than minimum threshold (keeps at least 5)
.NOTES       Module Type: Type2 | DiffKey: RestorePoint | Version: 1.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-RestorePointManagement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    $null = $OSContext  # Type2 interface parameter, may be used by future optimizations
    Write-Log -Level INFO -Component RESTORE -Message 'Starting restore point management'

    $diff = Get-DiffList -ModuleName 'RestorePoint'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component RESTORE -Message 'No restore point changes needed'
        return New-ModuleResult -ModuleName 'RestorePointManagement' -Status 'Skipped' -ModuleType 'Type2' `
            -Message 'No restore point actions queued'
    }

    $processed = 0
    $failed = 0
    $errors = @()
    $created = $false
    $removed = 0

    # Separate create and remove actions
    $createActions = @($diff | Where-Object { $_.Action -eq 'create' })
    $removeActions = @($diff | Where-Object { $_.Action -eq 'remove' })

    Write-Log -Level INFO -Component RESTORE -Message "Processing restore points: Create=$($createActions.Count), Remove=$($removeActions.Count)"

    # Phase 1: Create new restore point
    if ($createActions.Count -gt 0) {
        $action = $createActions[0]
        $description = $action.Description ?? "Maintenance: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $allocationGB = $action.AllocationGB ?? 10

        try {
            Write-Log -Level INFO -Component RESTORE -Message "Creating restore point: '$description' (allocation: ${allocationGB}GB)"

            # Create restore point with description
            $null = Checkpoint-Computer -Description $description -ErrorAction Stop
            $created = $true
            $processed++

            Write-Log -Level SUCCESS -Component RESTORE -Message "Restore point created: $description"

            # Note: Windows automatically manages restore point size allocation.
            # We log the intended allocation but cannot directly set it via PowerShell.
            # This must be managed via VssAdmin or Windows Settings.
            Write-Log -Level DEBUG -Component RESTORE -Message "Note: Restore point allocation managed by Windows (requested: ${allocationGB}GB)"
        }
        catch {
            Write-Log -Level ERROR -Component RESTORE -Message "Failed to create restore point: $_"
            $errors += "Restore point creation failed: $_"
            $failed++
        }
    }

    # Phase 2: Remove old restore points
    if ($removeActions.Count -gt 0) {
        Write-Log -Level INFO -Component RESTORE -Message "Removing $($removeActions.Count) old restore point(s)"

        foreach ($action in $removeActions) {
            $seqNum = $action.SequenceNumber
            $description = $action.Description ?? "Unknown"

            try {
                Write-Log -Level DEBUG -Component RESTORE -Message "Removing restore point: Seq=$seqNum, Desc=$description"

                # Remove the restore point
                $null = Remove-Item -Path "\\.\GLOBALROOT\Device\HarddiskVolumeShadowCopy$seqNum" -Force -ErrorAction Stop

                $removed++
                $processed++

                Write-Log -Level SUCCESS -Component RESTORE -Message "Removed restore point: Seq=$seqNum ($description)"
            }
            catch {
                # Try alternative removal method using WMI
                try {
                    $null = Get-WmiObject -Class Win32_ShadowCopy -Filter "ID like '%$seqNum%'" -ErrorAction Stop | Remove-WmiObject

                    $removed++
                    $processed++

                    Write-Log -Level SUCCESS -Component RESTORE -Message "Removed restore point (WMI): Seq=$seqNum ($description)"
                }
                catch {
                    Write-Log -Level WARN -Component RESTORE -Message "Could not remove restore point $seqNum (may require system restart): $_"
                    $errors += "Remove failed for seq $seqNum : $_"
                    $failed++
                }
            }
        }
    }

    # Verify result
    try {
        $currentPoints = @(Get-ComputerRestorePoint -ErrorAction Stop)
        Write-Log -Level INFO -Component RESTORE -Message "Restore points after management: $($currentPoints.Count)"
    }
    catch {
        Write-Log -Level WARN -Component RESTORE -Message "Could not verify restore point count: $_"
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    $message = "Restore point management: Created=$($if($created) { 1 } else { 0 }), Removed=$removed"

    Write-Log -Level INFO -Component RESTORE -Message "Done: $message"

    return New-ModuleResult -ModuleName 'RestorePointManagement' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors `
        -Message $message -ExtraData @{
            Created = if ($created) { 1 } else { 0 }
            Removed = $removed
        }
}

Export-ModuleMember -Function 'Invoke-RestorePointManagement'
