$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$reusableText = Get-Content -Raw -LiteralPath (Join-Path $root 'Reusable.ps1')
if ($reusableText -match 'function\s+(Invoke-FabText|Get-FabLongList|Get-FabItemDefinition|Convert-FixedWidthTableToObjects)') {
    throw 'fab execution is still hidden behind a wrapper or fixed-width parser.'
}

$expectedCommands = @{
    '01-Get-Capacities.ps1' = 'fab ls .capacities -l --output_format json'
    '02-Get-Workspaces.ps1' = 'fab ls -l --output_format json'
    '03-Get-WorkspaceItems.ps1' = 'fab ls $path -l --output_format json'
    '04-Get-SemanticModels.ps1' = 'fab get $path -q . -f --output_format json'
    '05-Get-Reports.ps1' = 'fab get $path -q . -f --output_format json'
}
foreach ($entry in $expectedCommands.GetEnumerator()) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $root "scripts\$($entry.Key)")
    if (-not $text.Contains($entry.Value)) { throw "$($entry.Key) does not contain the direct command: $($entry.Value)" }
}

$fixtureFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("fabric-inventory-fab17-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureFolder | Out-Null
try {
    function fab {
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -eq 'ls .capacities -l --output_format json') {
            '{"timestamp":"2026-10-07T00:00:00Z","status":"Success","command":"ls","result":{"data":[{"name":"Test.Capacity","id":"capacity-1","sku":"F2","region":"westeurope","state":"Active"}]}}'
            return
        }
        throw "Unexpected mocked fab command: $($args -join ' ')"
    }
    $outputPath = Join-Path $fixtureFolder 'capacities.json'
    $result = @(& (Join-Path $root 'scripts\01-Get-Capacities.ps1') -OutputPath $outputPath)
    if ($result.Count -ne 1 -or $result[0].name -ne 'Test' -or $result[0].id -ne 'capacity-1') { throw 'fab 1.7 JSON capacity output was not parsed correctly.' }
    $saved = @(Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json)
    if ($saved.Count -ne 1 -or $saved[0].sourceMethod -notmatch '--output_format json$') { throw 'Capacity JSON was not saved from the fab 1.7 envelope.' }
} finally {
    Remove-Item -Path Function:\fab -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureFolder -Recurse -Force
}

Write-Host 'fab 1.7 direct-command tests passed.'
