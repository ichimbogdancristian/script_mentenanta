try {
    $vcInstalled = $false
    $regPath = 'HKLM:\SOFTWARE\Classes\Installer\Dependencies\'
    $dependencies = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
    foreach ($dep in $dependencies) {
        $item = Get-ItemProperty -Path $dep.PSPath -ErrorAction SilentlyContinue
        if ($item.DisplayName -like '*Microsoft Visual C++ 2015-2022 Redistributable*x64*') {
            $vcInstalled = $true
            Write-Host "Found: $($item.DisplayName)"
            break
        }
    }
    if ($vcInstalled) {
        Write-Host '[INFO] Visual C++ Redistributable x64 is already installed'
        exit 0
    } else {
        Write-Host '[INFO] Visual C++ Redistributable x64 not found, installing...'
        exit 1
    }
} catch {
    Write-Host '[WARN] Registry check failed:' $_.Exception.Message
    exit 1
}
