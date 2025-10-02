Import-Module .\modules\type1\SystemInventory.psm1
$inv = Get-SystemInventory
Write-Host "InstalledSoftware Keys:"
$inv.InstalledSoftware.Keys
Write-Host "InstalledSoftware Programs count: $($inv.InstalledSoftware.Programs.Count)"
if ($inv.InstalledSoftware.Programs.Count -gt 0) {
    Write-Host "First program: $($inv.InstalledSoftware.Programs[0] | ConvertTo-Json -Depth 1)"
}