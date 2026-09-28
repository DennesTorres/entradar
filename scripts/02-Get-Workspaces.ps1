param([string]$OutputPath = (Join-Path $PSScriptRoot '..\output\workspaces.json'))
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$items = @(Get-FabLongList) | ForEach-Object {
    $capacityId = if ($_.capacityId -in @('', 'None', 'N/A')) { $null } else { $_.capacityId }
    [pscustomobject]@{ name = $_.name -replace '\.(Workspace|Personal)$',''; type = if ($_.name -match '\.([^.]+)$') { $Matches[1] } else { 'Workspace' }; id = $_.id; capacityId = $capacityId; capacityName = if ($_.capacityName -in @('', 'None', 'N/A')) { $null } else { $_.capacityName }; capacityRegion = if ($_.capacityRegion -in @('', 'Unknown')) { $null } else { $_.capacityRegion }; capacityAssignment = if ($capacityId) { 'assigned' } else { 'unassigned' }; sourceMethod = 'fab ls -l' }
}
Write-InventoryJson -InputObject @($items) -Path $OutputPath
$items
