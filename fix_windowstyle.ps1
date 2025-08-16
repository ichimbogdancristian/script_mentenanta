# Remove all -WindowStyle Hidden from PowerShell commands
$content = Get-Content "c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" -Raw
$content = $content -replace 'powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File', 'powershell -ExecutionPolicy Bypass -File'
$content = $content -replace '-WindowStyle Hidden', ''
Set-Content "c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" -Value $content -NoNewline
Write-Host "Removed all -WindowStyle Hidden parameters from script.bat"
