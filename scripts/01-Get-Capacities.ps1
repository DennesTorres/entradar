param([string]$OutputPath = (Join-Path $PSScriptRoot '..\output\capacities.json'))
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$fabOutput = fab ls .capacities -l --output_format json 2>&1
if ($LASTEXITCODE -ne 0) { throw "fab ls .capacities failed: $($fabOutput -join [Environment]::NewLine)" }
$fabResult = ($fabOutput -join [Environment]::NewLine) | ConvertFrom-Json
if ($fabResult.status -ne 'Success') { throw "fab ls .capacities failed: $($fabResult.result.message)" }
$items = @($fabResult.result.data) | ForEach-Object {
    [pscustomobject]@{ name = $_.name -replace '\.Capacity$',''; id = $_.id; sku = $_.sku; region = $_.region; state = $_.state; sourceMethod = 'fab ls .capacities -l --output_format json' }
}
Write-InventoryJson -InputObject @($items) -Path $OutputPath
$items
