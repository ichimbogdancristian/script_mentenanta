# Run PSScriptAnalyzer and save results
New-Item -Path .\temp_files\analysis -ItemType Directory -Force | Out-Null
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -AllowClobber -Confirm:$false
}
Import-Module PSScriptAnalyzer -Force
$results = Invoke-ScriptAnalyzer -Path . -Recurse -Settings '.\PSScriptAnalyzerSettings.psd1' -Severity Error, Warning -Force
$out = $results | Select-Object @{n = 'File'; e = { $_.ScriptName } }, Line, RuleName, Severity, Message
$out | ConvertTo-Json -Depth 5 | Out-File -FilePath '.\temp_files\analysis\psscriptanalyzer-results.json' -Encoding UTF8 -Force
if ($results.Count -gt 0) {
    $out | Format-Table -AutoSize
    exit 2
}
else {
    Write-Host 'No issues found'
    exit 0
}
