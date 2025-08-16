$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/microsoft-ui-xaml/releases/latest'
Write-Host "Latest Microsoft.UI.Xaml version: $($release.tag_name)"
$assets = $release.assets | Where-Object { $_.name -like '*nupkg' }
if ($assets) {
    $assets | Select-Object name, browser_download_url
} else {
    Write-Host "No nupkg files found, checking all assets:"
    $release.assets | Select-Object name, browser_download_url
}
