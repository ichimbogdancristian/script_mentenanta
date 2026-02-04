param(
    [string]$RootPath = (Resolve-Path .).Path
)

$psFiles = Get-ChildItem -Path $RootPath -Recurse -Include *.psm1, *.ps1 | Where-Object {
    $_.FullName -notmatch '\\archived\\'
}

$analysis = @()
foreach ($f in $psFiles) {
    $content = Get-Content $f.FullName -Raw
    $funcs = [regex]::Matches($content, '(?m)^\s*function\s+([A-Za-z0-9_-]+)') | ForEach-Object { $_.Groups[1].Value }
    $exports = [regex]::Matches($content, '(?ms)Export-ModuleMember\s+-Function\s+@\((.*?)\)') | ForEach-Object { $_.Groups[1].Value }
    $exportsSingle = [regex]::Matches($content, '(?m)Export-ModuleMember\s+-Function\s+([A-Za-z0-9_-]+)') | ForEach-Object { $_.Groups[1].Value }

    $exportList = @()
    foreach ($e in $exports) {
        $exportList += (
            $e -split "[,\r\n]" |
            ForEach-Object {
                $clean = $_.Trim()
                $clean = $clean.Trim("'")
                $clean = $clean.Trim('"')
                $clean
            } |
            Where-Object { $_ }
        )
    }

    if ($exportsSingle) {
        $exportList += $exportsSingle
    }

    $analysis += [pscustomobject]@{
        File          = $f.FullName
        FunctionCount = $funcs.Count
        Functions     = $funcs
        Exported      = $exportList
    }
}

$dupFuncs = $analysis.Functions | Group-Object | Where-Object { $_.Count -gt 1 } | Sort-Object Count -Descending
$exportsMissing = $analysis | Where-Object { $_.File -match '\.psm1$' -and $_.Exported.Count -eq 0 }

$hardcodedPaths = @()
foreach ($f in $psFiles) {
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(temp_files|config\\|modules\\|logs\\|reports\\)') {
            $hardcodedPaths += [pscustomobject]@{
                File = $f.FullName
                Line = $i + 1
                Text = $lines[$i].Trim()
            }
        }
    }
}

$results = [pscustomobject]@{
    TotalFiles         = $psFiles.Count
    DuplicateFunctions = ($dupFuncs | Select-Object Name, Count)
    MissingExports     = $exportsMissing.File
    HardcodedPathHits  = $hardcodedPaths
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $RootPath 'analysis-core-scan.json')

Write-Host "Analysis written to analysis-core-scan.json"