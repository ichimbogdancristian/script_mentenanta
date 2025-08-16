# Add error redirection to PowerShell commands that don't have it
$content = Get-Content "c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" -Raw
$content = $content -replace 'powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%"(?!\s*2>&1)', 'powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1'
Set-Content "c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" -Value $content -NoNewline
Write-Host "Added error redirection to all PowerShell commands in script.bat"
