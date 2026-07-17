#Requires -Version 7.0
<#
.SYNOPSIS    Disk Cleanup Audit - Type 1
.DESCRIPTION Audits temp files, browser cache/cookies (Chrome/Edge/Firefox, all local
             user profiles), Windows Update component-store cleanup eligibility, and
             Recycle Bin contents. Diff = cleanup candidates that actually have
             reclaimable size, with an estimated size in MB per item.
.NOTES       Module Type: Type1 | DiffKey: DiskCleanup | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

<#
.SYNOPSIS
    Recursively sums file sizes under a path, tolerating locked/inaccessible files.
.OUTPUTS
    [double] Size in MB, rounded to 1 decimal. 0 if the path doesn't exist or is empty.
#>
function Get-FolderSizeMB {
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)] [string]$Path)

    # -ErrorAction SilentlyContinue on Test-Path itself: some profile folders picked
    # up from C:\Users (e.g. IIS app-pool identities like DefaultAppPool) are not
    # readable by an interactively-elevated admin session even though the whole
    # tool runs elevated, and Test-Path surfaces that as a non-terminating error
    # rather than just returning $false — tolerate it the same as any other
    # inaccessible path instead of letting it interrupt the audit.
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return 0 }
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if (-not $bytes) { return 0 }
        return [math]::Round($bytes / 1MB, 1)
    }
    catch { return 0 }
}

<#
.SYNOPSIS
    Returns local user profile directories under C:\Users, excluding system/shared
    pseudo-profiles (Public, Default, Default User, All Users) that don't hold
    per-user browser/temp data.
#>
function Get-LocalUserProfileDirs {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path $usersRoot -ErrorAction SilentlyContinue)) { return @() }
    $excluded = @('Public', 'Default', 'Default User', 'All Users')
    return @(Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $excluded } |
        ForEach-Object { $_.FullName })
}

function Invoke-DiskCleanupAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component DISKCLEAN-AUDIT -Message 'Starting disk cleanup audit'

    try {
        $config = Get-BaselineList -ModuleFolder 'disk-cleanup' -FileName 'disk-cleanup-config.json'
        if (-not $config) {
            return New-ModuleResult -ModuleName 'DiskCleanupAudit' -Status 'Failed' `
                -Message 'Disk cleanup config not found'
        }

        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $userProfiles = Get-LocalUserProfileDirs

        # 1. Temp files: Use config-driven paths with environment variable expansion
        if ($config.tempFiles.enabled) {
            $minMB = $config.tempFiles.minSizeMB ?? 1
            $tempTargets = [System.Collections.Generic.List[hashtable]]::new()

            # Add configured common temp paths
            if ($config.tempFiles.paths) {
                foreach ($pathConfig in $config.tempFiles.paths) {
                    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($pathConfig.path)
                    $tempTargets.Add(@{
                        Name = $pathConfig.name
                        Path = $expandedPath
                    })
                }
            }
            else {
                # Fallback to hardcoded paths if config is missing
                Write-Log -Level WARN -Component DISKCLEAN-AUDIT -Message 'Temp paths not in config, using fallback paths'
                $tempTargets.Add(@{ Name = 'Current Session Temp'; Path = $env:TEMP })
                $tempTargets.Add(@{ Name = 'Windows Temp'; Path = (Join-Path $env:SystemRoot 'Temp') })
            }

            # Add per-user temp paths
            foreach ($profileDir in $userProfiles) {
                $userName = Split-Path $profileDir -Leaf
                $userTemp = Join-Path $profileDir 'AppData\Local\Temp'
                $tempTargets.Add(@{ Name = "User Temp ($userName)"; Path = $userTemp })
            }

            foreach ($t in $tempTargets) {
                $sizeMB = Get-FolderSizeMB -Path $t.Path
                if ($sizeMB -ge $minMB) {
                    $diff.Add(@{
                            Type        = 'temp'
                            Name        = $t.Name
                            Path        = $t.Path
                            SizeMB      = $sizeMB
                            Description = "$($t.Name): $sizeMB MB reclaimable"
                        })
                    Write-Log -Level DEBUG -Component DISKCLEAN-AUDIT -Message "$($t.Name): $sizeMB MB"
                }
            }
        }

        # 2. Browser cache/cookies — Chrome, Edge, Firefox, every local user profile (paths from config)
        if ($config.browsers.enabled) {
            $minMB = $config.browsers.minSizeMB ?? 1
            foreach ($profileDir in $userProfiles) {
                $userName = Split-Path $profileDir -Leaf

                if ($config.browsers.chrome -and $config.browsers.paths.chrome) {
                    $chromeRoot = [System.Environment]::ExpandEnvironmentVariables($config.browsers.paths.chrome.root)
                    Add-BrowserDiffItems -Diff $diff -BrowserRoot $chromeRoot -BrowserName 'Chrome' `
                        -UserName $userName -Config $config -MinMB $minMB
                }
                elseif ($config.browsers.chrome) {
                    $chromeRoot = Join-Path $profileDir 'AppData\Local\Google\Chrome\User Data'
                    Add-BrowserDiffItems -Diff $diff -BrowserRoot $chromeRoot -BrowserName 'Chrome' `
                        -UserName $userName -Config $config -MinMB $minMB
                }

                if ($config.browsers.edge -and $config.browsers.paths.edge) {
                    $edgeRoot = [System.Environment]::ExpandEnvironmentVariables($config.browsers.paths.edge.root)
                    Add-BrowserDiffItems -Diff $diff -BrowserRoot $edgeRoot -BrowserName 'Edge' `
                        -UserName $userName -Config $config -MinMB $minMB
                }
                elseif ($config.browsers.edge) {
                    $edgeRoot = Join-Path $profileDir 'AppData\Local\Microsoft\Edge\User Data'
                    Add-BrowserDiffItems -Diff $diff -BrowserRoot $edgeRoot -BrowserName 'Edge' `
                        -UserName $userName -Config $config -MinMB $minMB
                }

                if ($config.browsers.firefox) {
                    Add-FirefoxDiffItems -Diff $diff -ProfileDir $profileDir -UserName $userName `
                        -Config $config -MinMB $minMB
                }
            }
        }

        # 3. Windows Update component-store cleanup — only if DISM's own analysis
        # says it's actually worth doing (avoids a slow no-op cleanup pass)
        if ($config.windowsUpdateCleanup.enabled) {
            try {
                $dismExe = Join-Path $env:SystemRoot 'System32\dism.exe'
                $analysis = & $dismExe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
                if ($analysis -match 'Component Store Cleanup Recommended\s*:\s*Yes') {
                    $diff.Add(@{
                            Type        = 'update-cleanup'
                            Name        = 'Windows Update Component Cleanup'
                            ResetBase   = [bool]($config.windowsUpdateCleanup.resetBase)
                            Description = 'DISM component store cleanup recommended'
                        })
                    Write-Log -Level DEBUG -Component DISKCLEAN-AUDIT -Message 'DISM recommends component store cleanup'
                }
            }
            catch { Write-Log -Level WARN -Component DISKCLEAN-AUDIT -Message "DISM component store analysis failed: $_" }
        }

        # 4. Recycle Bin — every fixed drive
        if ($config.recycleBin.enabled) {
            $minMB = $config.recycleBin.minSizeMB ?? 1
            $fixedDrives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
            foreach ($drive in $fixedDrives) {
                $letter = $drive.Name.TrimEnd('\')
                $binPath = Join-Path $drive.Name '$Recycle.Bin'
                $sizeMB = Get-FolderSizeMB -Path $binPath
                if ($sizeMB -ge $minMB) {
                    $diff.Add(@{
                            Type        = 'recyclebin'
                            Name        = "Recycle Bin ($letter)"
                            Drive       = $letter
                            SizeMB      = $sizeMB
                            Description = "Recycle Bin on $letter`: $sizeMB MB reclaimable"
                        })
                    Write-Log -Level DEBUG -Component DISKCLEAN-AUDIT -Message "Recycle Bin $letter`: $sizeMB MB"
                }
            }
        }

        $totalMB = ($diff | ForEach-Object { [double]($_.SizeMB ?? 0) } | Measure-Object -Sum).Sum
        Write-Log -Level INFO -Component DISKCLEAN-AUDIT -Message "Cleanup candidates: $($diff.Count), ~$totalMB MB reclaimable"

        # 5. Save diff
        Save-DiffList -ModuleName 'DiskCleanup' -DiffList $diff.ToArray()

        return New-ModuleResult -ModuleName 'DiskCleanupAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) cleanup candidate(s), ~$totalMB MB reclaimable"
    }
    catch {
        Write-Log -Level ERROR -Component DISKCLEAN-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'DiskCleanupAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

<#
.SYNOPSIS
    Adds Chrome/Edge-style (Chromium) cache and cookie diff items for one browser
    root, covering every profile folder (Default, Profile 1, Profile 2, ...).
#>
function Add-BrowserDiffItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[hashtable]]$Diff,
        [Parameter(Mandatory)] [string]$BrowserRoot,
        [Parameter(Mandatory)] [string]$BrowserName,
        [Parameter(Mandatory)] [string]$UserName,
        [Parameter(Mandatory)] [hashtable]$Config,
        [Parameter(Mandatory)] [double]$MinMB
    )

    if (-not (Test-Path $BrowserRoot -ErrorAction SilentlyContinue)) { return }
    $profileDirs = @(Get-ChildItem -Path $BrowserRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })

    foreach ($p in $profileDirs) {
        if ($Config.browsers.clearCache) {
            $cachePath = Join-Path $p.FullName 'Cache'
            $sizeMB = Get-FolderSizeMB -Path $cachePath
            if ($sizeMB -ge $MinMB) {
                $Diff.Add(@{
                        Type        = 'browser-cache'
                        Name        = "$BrowserName Cache - $($p.Name) ($UserName)"
                        Path        = $cachePath
                        SizeMB      = $sizeMB
                        Description = "$BrowserName cache for $UserName/$($p.Name): $sizeMB MB"
                    })
            }
        }
        if ($Config.browsers.clearCookies) {
            # Chromium moved Cookies into a Network\ subfolder in recent versions;
            # check both locations since either may be present depending on version.
            foreach ($cookiePath in @((Join-Path $p.FullName 'Network\Cookies'), (Join-Path $p.FullName 'Cookies'))) {
                if (Test-Path $cookiePath -ErrorAction SilentlyContinue) {
                    $Diff.Add(@{
                            Type        = 'browser-cookies'
                            Name        = "$BrowserName Cookies - $($p.Name) ($UserName)"
                            Path        = $cookiePath
                            SizeMB      = [math]::Round((Get-Item $cookiePath -ErrorAction SilentlyContinue).Length / 1MB, 2)
                            Description = "$BrowserName cookies for $UserName/$($p.Name)"
                        })
                    break
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Adds Firefox cache and cookie diff items, covering every profile folder.
#>
function Add-FirefoxDiffItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[hashtable]]$Diff,
        [Parameter(Mandatory)] [string]$ProfileDir,
        [Parameter(Mandatory)] [string]$UserName,
        [Parameter(Mandatory)] [hashtable]$Config,
        [Parameter(Mandatory)] [double]$MinMB
    )

    $ffLocalRoot = Join-Path $ProfileDir 'AppData\Local\Mozilla\Firefox\Profiles'
    $ffRoamingRoot = Join-Path $ProfileDir 'AppData\Roaming\Mozilla\Firefox\Profiles'

    if ($Config.browsers.clearCache -and (Test-Path $ffLocalRoot -ErrorAction SilentlyContinue)) {
        foreach ($p in (Get-ChildItem -Path $ffLocalRoot -Directory -ErrorAction SilentlyContinue)) {
            $cachePath = Join-Path $p.FullName 'cache2'
            $sizeMB = Get-FolderSizeMB -Path $cachePath
            if ($sizeMB -ge $MinMB) {
                $Diff.Add(@{
                        Type        = 'browser-cache'
                        Name        = "Firefox Cache - $($p.Name) ($UserName)"
                        Path        = $cachePath
                        SizeMB      = $sizeMB
                        Description = "Firefox cache for $UserName/$($p.Name): $sizeMB MB"
                    })
            }
        }
    }
    if ($Config.browsers.clearCookies -and (Test-Path $ffRoamingRoot -ErrorAction SilentlyContinue)) {
        foreach ($p in (Get-ChildItem -Path $ffRoamingRoot -Directory -ErrorAction SilentlyContinue)) {
            $cookiePath = Join-Path $p.FullName 'cookies.sqlite'
            if (Test-Path $cookiePath -ErrorAction SilentlyContinue) {
                $Diff.Add(@{
                        Type        = 'browser-cookies'
                        Name        = "Firefox Cookies - $($p.Name) ($UserName)"
                        Path        = $cookiePath
                        SizeMB      = [math]::Round((Get-Item $cookiePath -ErrorAction SilentlyContinue).Length / 1MB, 2)
                        Description = "Firefox cookies for $UserName/$($p.Name)"
                    })
            }
        }
    }
}

Export-ModuleMember -Function 'Invoke-DiskCleanupAudit'
