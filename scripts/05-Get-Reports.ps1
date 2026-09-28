param([string]$ItemsPath = (Join-Path $PSScriptRoot '..\output\items.json'), [string]$OutputPath = (Join-Path $PSScriptRoot '..\output\reports.json'))
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$inventory = Get-Content -Raw -LiteralPath $ItemsPath | ConvertFrom-Json
$targets = @($inventory.items | Where-Object type -eq 'Report')
$reports = @(); $errors = @(); $i = 0
foreach ($target in $targets) {
    $i++; Show-InventoryProgress -Current $i -Total $targets.Count -Message "$($target.workspaceName)/$($target.name)"
    $path = "$($target.workspacePath)/$(ConvertTo-FabPathSegment $target.name).Report"
    try { $reports += ConvertFrom-PbirReport -Definition (Get-FabItemDefinition -Path $path) -WorkspaceName $target.workspaceName }
    catch { $errors += [pscustomobject]@{ id = $target.id; name = $target.name; workspaceId = $target.workspaceId; workspaceName = $target.workspaceName; sourceMethod = 'fab get (native)'; coverageStatus = 'failed'; error = $_.Exception.Message } }
}
Write-Progress -Activity 'Fabric inventory' -Completed
Write-InventoryJson -InputObject ([pscustomobject]@{ reports = $reports; errors = $errors }) -Path $OutputPath
[pscustomobject]@{ reports = $reports; errors = $errors }
