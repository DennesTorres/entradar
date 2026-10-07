param(
    [Parameter(Mandatory)][string]$Path,
    [string]$WorkspaceName = 'Preflight'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')

$fabOutput = fab get $Path -q . -f --output_format json 2>&1
if ($LASTEXITCODE -ne 0) { throw "fab get '$Path' failed: $($fabOutput -join [Environment]::NewLine)" }
$fabText = $fabOutput -join [Environment]::NewLine
$jsonStart = $fabText.IndexOf('{')
if ($jsonStart -lt 0) { throw "fab get '$Path' returned no JSON." }
$fabResult = $fabText.Substring($jsonStart) | ConvertFrom-Json
if ($fabResult.status -ne 'Success') { throw "fab get '$Path' failed: $($fabResult.result.message)" }
$definition = @($fabResult.result.data)[0]
if ($null -eq $definition) { throw "fab get '$Path' returned no definition." }
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
