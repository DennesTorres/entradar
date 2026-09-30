$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$reusableText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\Reusable.ps1')
if ($reusableText.Contains("'-f'") -or $reusableText.Contains("'--force'")) { throw 'Get-FabItemDefinition includes a force option.' }
if (-not (Test-FabSyntaxError -Message "unknown shorthand flag: 'force'")) { throw 'fab syntax-error detection failed.' }

function fab {
    if ($args -contains '-f' -or $args -contains '--force') { $global:LASTEXITCODE = 1; "unknown shorthand flag: 'force'"; return }
    $global:LASTEXITCODE = 0
    '{"id":"mock-id","displayName":"Mock","workspaceId":"mock-workspace","connections":[],"definition":{"format":"TMDL","parts":[]}}'
}
$mockDefinition = Get-FabItemDefinition -Path 'Mock.Workspace/Mock.SemanticModel'
Remove-Item -Path Function:\fab
if ($mockDefinition.id -ne 'mock-id') { throw 'fab get without a force option failed.' }
$sample = @(
    'name                  id                                     capacityId',
    '-----------------------------------------------------------------------',
    'Demo.Workspace        11111111-1111-1111-1111-111111111111   None'
)
$parsed = @($sample | Convert-FixedWidthTableToObjects)
if ($parsed.Count -ne 1 -or $parsed[0].name -ne 'Demo.Workspace' -or $parsed[0].capacityId -ne 'None') { throw 'Fixed-width parser test failed.' }
$definition = [pscustomobject]@{ id='m1'; displayName='Model'; workspaceId='w1'; connections=@([pscustomobject]@{ id='c1' }); definition=[pscustomobject]@{ format='TMDL'; parts=@(
    [pscustomobject]@{ path='definition/tables/T.tmdl'; payload="table T`n`tcolumn Id`n`t`tdataType: int64`n`tmeasure Base = SUM(T[Id])`n`tmeasure Derived = [Base] * 2`n`tpartition T = m`n`t`tmode: import`n`t`tsource = Sql.Database(`"server`", `"db`")" },
    [pscustomobject]@{ path='definition/relationships.tmdl'; payload="relationship r1`n`tfromColumn: T.Id`n`ttoColumn: D.Id" }
) } }
$model = ConvertFrom-TmdlSemanticModel -Definition $definition -WorkspaceName 'W'
if ($model.tables.Count -ne 1 -or $model.columns.Count -ne 1 -or $model.measures.Count -ne 2 -or $model.relationships.Count -ne 1) { throw 'TMDL parser count test failed.' }
if (@($model.measures | Where-Object name -eq 'Derived').dependencies -notcontains 'Base') { throw 'Measure dependency test failed.' }
Write-Host 'Reusable tests passed.'
