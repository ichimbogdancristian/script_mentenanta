Import-Module .\modules\type1\SystemInventory.psm1
$inv = Get-SystemInventory
Write-Host "SystemInventory Keys:"
$inv.Keys
Write-Host "InstalledApps property exists: $($inv.ContainsKey('InstalledApps'))"
if ($inv.InstalledApps) {
    Write-Host "InstalledApps count: $($inv.InstalledApps.Count)"
    if ($inv.InstalledApps.Count -gt 0) {
        Write-Host "First app: $($inv.InstalledApps[0] | ConvertTo-Json -Depth 1)"
    }
}