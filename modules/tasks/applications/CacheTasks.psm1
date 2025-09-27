# CacheTasks.psm1 - Application cache cleaning tasks
# Contains tasks related to cleaning application caches and temporary data

# ================================================================
# Function: Clear-ApplicationCache
# ================================================================
# Purpose: Clean application caches and temporary data
# ================================================================
function Clear-ApplicationCache {
    Write-Log "Cleaning application caches..." 'INFO'

    $cleanedSize = 0

    try {
        # Clean Windows Store cache
        try {
            Start-Process wsreset.exe -ArgumentList "/reset" -NoNewWindow -Wait -PassThru
            Write-Log "Windows Store cache reset" 'INFO'
        }
        catch {
            Write-Log "Failed to reset Windows Store cache: $_" 'WARN'
        }

        # Clean browser caches (example for common browsers)
        $browserCachePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*.default\cache2"
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        )

        foreach ($cachePath in $browserCachePaths) {
            try {
                if (Test-Path $cachePath) {
                    $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $cleanedSize += $cacheSize
                    Write-Log "Cleaned browser cache: $cachePath" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to clean cache $cachePath`: $_" 'WARN'
            }
        }

        $cleanedMB = [math]::Round($cleanedSize / 1MB, 2)
        Write-Log "Application cache cleaning completed: ${cleanedMB}MB cleaned" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Critical error during cache cleaning: $_" 'ERROR'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Clear-ApplicationCache