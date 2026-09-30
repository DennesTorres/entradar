param(
    [Parameter(Mandatory)][string]$Path,
    [string]$WorkspaceName = 'Preflight'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')

$definition = Get-FabItemDefinition -Path $Path
$result = [ordered]@{
    path = $Path
    id = $definition.id
    name = $definition.displayName
    format = $definition.definition.format
    definitionParts = @($definition.definition.parts).Count
}
if ($Path -like '*.SemanticModel') {
    $model = ConvertFrom-TmdlSemanticModel -Definition $definition -WorkspaceName $WorkspaceName
    $result.tables = @($model.tables).Count
    $result.columns = @($model.columns).Count
    $result.measures = @($model.measures).Count
    $result.relationships = @($model.relationships).Count
}
[pscustomobject]$result | Format-List
Write-Host 'Live definition preflight passed.'
