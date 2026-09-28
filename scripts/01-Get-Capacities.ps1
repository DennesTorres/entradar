param([string]$OutputPath = (Join-Path $PSScriptRoot '..\output\capacities.json'))
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$items = @(Get-FabLongList -Path '.capacities') | ForEach-Object {
    [pscustomobject]@{ name = $_.name -replace '\.Capacity$',''; id = $_.id; sku = $_.sku; region = $_.region; state = $_.state; sourceMethod = 'fab ls .capacities -l' }
}
Write-InventoryJson -InputObject @($items) -Path $OutputPath
$items
