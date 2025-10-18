$root = 'c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta'
$coreModules = @('CoreInfrastructure', 'UserInterface', 'LogProcessor', 'ReportGenerator')
foreach ($m in $coreModules) {
    $p = Join-Path $root "modules\core\$m.psm1"
    Write-Output "CORE: $m -> $p"
    try { Import-Module $p -Force -ErrorAction Stop; Write-Output '  OK' } catch { Write-Output ("  ERR: $($_.Exception.Message)") }
}

$type2 = @('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates')
foreach ($m in $type2) {
    $p = Join-Path $root "modules\type2\$m.psm1"
    Write-Output "TYPE2: $m -> $p"
    try { Import-Module $p -Force -ErrorAction Stop; Write-Output '  OK'; $inv = "Invoke-$m"; if (Get-Command -Name $inv -ErrorAction SilentlyContinue) { Write-Output "   HAS_FN: $inv" } else { Write-Output "   MISSING_FN: $inv" } } catch { Write-Output ("  ERR: $($_.Exception.Message)"); if ($_.ScriptStackTrace) { Write-Output ("  STACK: $((($_.ScriptStackTrace -split "`n") | Select-Object -First 3) -join ' ; ')") } }
}
