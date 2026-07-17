#Requires -Version 7.0
<#
.SYNOPSIS    System Optimization - Type 2 (system modification)
.DESCRIPTION Applies service startup changes, power plan, and visual effects settings
             identified as non-compliant during the audit diff.
.NOTES       Module Type: Type2 | DiffKey: SystemOptimization | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component SYSOPT -Message 'Starting system optimization'

    $diff = Get-DiffList -ModuleName 'SystemOptimization'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component SYSOPT -Message 'System already optimized'
        return New-ModuleResult -ModuleName 'SystemOptimization' -Status 'Skipped' -Message 'No changes needed'
    }

    $osCtx     = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component SYSOPT -Message "Applying $($diff.Count) optimization(s) on $($osCtx.DisplayText)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        try {
            $changed = $false
            switch ($type) {
                'service' {
                    $svc   = $item.ServiceName ?? $item.Name
                    $start = $item.DesiredStartType ?? $item.DesiredState ?? 'Disabled'
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svc -StartupType $start -ErrorAction Stop
                    Write-Log -Level SUCCESS -Component SYSOPT -Message "Service '$svc' -> $start"
                    $changed = $true
                }
                'powerplan' {
                    $planGuid = $item.GUID ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # High performance
                    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                    $null = & $powercfg /setactive $planGuid 2>&1
                    Write-Log -Level SUCCESS -Component SYSOPT -Message "Power plan set to GUID $planGuid"
                    $changed = $true
                }
                'registry' {
                    $path  = $item.Path ?? $item.RegistryPath
                    $vname = $item.ValueName ?? $item.Name
                    $val   = $item.DesiredValue
                    $vtype = $item.ValueType ?? 'DWord'
                    if ($path -and $null -ne $val) {
                        $null = Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
                        Write-Log -Level SUCCESS -Component SYSOPT -Message "Registry set: $path\$vname = $val"
                        $changed = $true
                    }
                }
                'visualfx' {
                    # Set balanced visual effects: Custom (3) with specific tweaks
                    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                    $null = Set-RegistryValue -Path $regPath -Name 'VisualFXSetting' -Value 3 -Type DWord

                    # Apply balanced UserPreferencesMask: disable animations/shadows/transparency, keep smooth fonts + window contents
                    $advancedPath = 'HKCU:\Control Panel\Desktop'
                    # Disable window animation (MinAnimate)
                    $null = Set-RegistryValue -Path $advancedPath -Name 'MinAnimate' -Value '0' -Type String
                    # Keep font smoothing on
                    $null = Set-RegistryValue -Path $advancedPath -Name 'FontSmoothing' -Value '2' -Type String
                    # Disable drag full windows (=0 for off, =1 for on) — keep enabled for usability
                    $null = Set-RegistryValue -Path $advancedPath -Name 'DragFullWindows' -Value '1' -Type String

                    # Disable taskbar animations
                    $advancedPath2 = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                    $null = Set-RegistryValue -Path $advancedPath2 -Name 'TaskbarAnimations' -Value 0 -Type DWord
                    # Disable ListviewShadow (icon shadows)
                    $null = Set-RegistryValue -Path $advancedPath2 -Name 'ListviewShadow' -Value 0 -Type DWord

                    # Disable transparency
                    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
                    $null = Set-RegistryValue -Path $personalize -Name 'EnableTransparency' -Value 0 -Type DWord

                    Write-Log -Level SUCCESS -Component SYSOPT -Message 'Visual effects set to balanced (custom)'
                    $changed = $true
                }
                'background' {
                    # Disable Windows Spotlight, set background to Picture
                    $cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                    $null = Set-RegistryValue -Path $cdmPath -Name 'RotatingLockScreenEnabled' -Value 0 -Type DWord
                    $null = Set-RegistryValue -Path $cdmPath -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord
                    $null = Set-RegistryValue -Path $cdmPath -Name 'SubscribedContent-338387Enabled' -Value 0 -Type DWord

                    # Set desktop wallpaper type to Picture (WallpaperStyle registry)
                    $wallpaperPath = 'HKCU:\Control Panel\Desktop'
                    $null = Set-RegistryValue -Path $wallpaperPath -Name 'WallpaperStyle' -Value '10' -Type String
                    $null = Set-RegistryValue -Path $wallpaperPath -Name 'TileWallpaper' -Value '0' -Type String

                    Write-Log -Level SUCCESS -Component SYSOPT -Message 'Desktop background changed from Spotlight to Picture'
                    $changed = $true
                }
                'startup' {
                    $regPath = $item.RegistryPath
                    $entryName = $item.Name
                    if ($regPath -and $entryName) {
                        Remove-ItemProperty -Path $regPath -Name $entryName -Force -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component SYSOPT -Message "Startup program disabled: $entryName"
                        $changed = $true
                    }
                }
                default {
                    Write-Log -Level WARN -Component SYSOPT -Message "Unknown optimization type '$type' for $name"
                }
            }
            if ($changed) { $processed++ }
        }
        catch {
            Write-Log -Level ERROR -Component SYSOPT -Message "Failed [$name / $type]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SYSOPT -Message "Done: $processed applied, $failed failed"
    return New-ModuleResult -ModuleName 'SystemOptimization' -Status $status -ItemsDetected $diff.Count `
                            -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SystemOptimization'
