param(
    [string]$WorkspacesPath = (Join-Path $PSScriptRoot '..\output\workspaces.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\output\items.json'),
    [string[]]$WorkspaceName
)
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$workspaces = Get-Content -Raw -LiteralPath $WorkspacesPath | ConvertFrom-Json
$workspaces = @($workspaces)
if ($WorkspaceName) { $workspaces = @($workspaces | Where-Object name -in $WorkspaceName) }
$items = @(); $errors = @(); $i = 0
foreach ($workspace in $workspaces) {
    $i++; Show-InventoryProgress -Current $i -Total $workspaces.Count -Message $workspace.name
    $path = "$(ConvertTo-FabPathSegment $workspace.name).$($workspace.type)"
    try {
        foreach ($item in @(Get-FabLongList -Path $path)) {
            $type = if ($item.name -match '\.([^.]+)$') { $Matches[1] } else { 'Unknown' }
            $items += [pscustomobject]@{ name = $item.name -replace '\.[^.]+$',''; type = $type; id = $item.id; workspaceId = $workspace.id; workspaceName = $workspace.name; workspacePath = $path; sourceMethod = "fab ls '$path' -l" }
        }
    } catch { $errors += [pscustomobject]@{ workspaceId = $workspace.id; workspaceName = $workspace.name; error = $_.Exception.Message } }
}
Write-Progress -Activity 'Fabric inventory' -Completed
Write-InventoryJson -InputObject ([pscustomobject]@{ items = $items; errors = $errors }) -Path $OutputPath
[pscustomobject]@{ items = $items; errors = $errors }
