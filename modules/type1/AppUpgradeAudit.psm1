#Requires -Version 7.0
<#
.SYNOPSIS    Application Upgrade Audit - Type 1
.DESCRIPTION Queries winget/chocolatey for available upgrades, filtered by exclude patterns.
             Diff = list of upgradeable apps.
.NOTES       Module Type: Type1 | DiffKey: AppUpgrade | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-AppUpgradeAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component UPGRADE-AUDIT -Message 'Starting app upgrade audit'

    try {
        # 1. Load config
        $config = Get-BaselineList -ModuleFolder 'app-upgrade' -FileName 'app-upgrade-config.json'
        if (-not $config -or $config.ModuleEnabled -eq $false) {
            Write-Log -Level INFO -Component UPGRADE-AUDIT -Message 'App upgrade disabled in config'
            Save-DiffList -ModuleName 'AppUpgrade' -DiffList @()
            return New-ModuleResult -ModuleName 'AppUpgradeAudit' -Status 'Skipped' `
                                    -Message 'Disabled in configuration'
        }

        $excludePatterns = if ($config.ExcludePatterns) { $config.ExcludePatterns } else { @() }
        $upgradeable = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Winget upgrades
        if ((Test-CommandAvailable 'winget') -and $config.EnabledSources -contains 'Winget') {
            Write-Log -Level INFO -Component UPGRADE-AUDIT -Message 'Querying winget for upgrades...'
            $wingetItems = Get-WingetUpgrade
            foreach ($item in $wingetItems) {
                if (-not $item.Name) { continue }
                $excluded = $false
                foreach ($pattern in $excludePatterns) {
                    if ($item.Name -like $pattern -or $item.Id -like $pattern) {
                        $excluded = $true; break
                    }
                }
                if (-not $excluded) {
                    $upgradeable.Add(@{
                        Name             = $item.Name
                        Id               = $item.Id
                        CurrentVersion   = $item.CurrentVersion
                        AvailableVersion = $item.AvailableVersion
                        Source           = 'Winget'
                    })
                    Write-Log -Level DEBUG -Component UPGRADE-AUDIT -Message "Upgrade available: $($item.Name) $($item.CurrentVersion)->$($item.AvailableVersion)"
                }
            }
        }
        else {
            Write-Log -Level INFO -Component UPGRADE-AUDIT -Message 'winget not available or not in enabled sources'
        }

        # 3. Chocolatey upgrades
        if ((Test-CommandAvailable 'choco') -and $config.EnabledSources -contains 'Chocolatey') {
            Write-Log -Level INFO -Component UPGRADE-AUDIT -Message 'Querying chocolatey for upgrades...'
            try {
                $chocoOutput = & choco outdated --no-progress --no-color 2>&1 | Where-Object { $_ -is [string] }
                foreach ($line in $chocoOutput) {
                    if ($line -match '^(\S+)\|(\S+)\|(\S+)') {
                        $pname = $Matches[1]; $curVer = $Matches[2]; $newVer = $Matches[3]
                        $excluded = $false
                        foreach ($pattern in $excludePatterns) {
                            if ($pname -like $pattern) { $excluded = $true; break }
                        }
                        if (-not $excluded) {
                            $upgradeable.Add(@{
                                Name = $pname; Id = $pname
                                CurrentVersion = $curVer; AvailableVersion = $newVer; Source = 'Chocolatey'
                            })
                        }
                    }
                }
            }
            catch { Write-Log -Level WARN -Component UPGRADE-AUDIT -Message "choco outdated failed: $_" }
        }

        Write-Log -Level INFO -Component UPGRADE-AUDIT -Message "Upgradeable apps: $($upgradeable.Count)"

        # 4. Save diff
        Save-DiffList -ModuleName 'AppUpgrade' -DiffList $upgradeable.ToArray()

        # 5. Persist
        $auditPath = Get-TempPath -Category 'data' -FileName 'appupgrade-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Upgradeable = $upgradeable.ToArray() } `
            | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component UPGRADE-AUDIT -Message "App upgrade audit complete: $($upgradeable.Count) upgrades available"
        return New-ModuleResult -ModuleName 'AppUpgradeAudit' -Status 'Success' `
                                -ItemsDetected $upgradeable.Count `
                                -Message "$($upgradeable.Count) upgrades available"
    }
    catch {
        Write-Log -Level ERROR -Component UPGRADE-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'AppUpgradeAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-AppUpgradeAudit'
