$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$reusableText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\Reusable.ps1')
if ($reusableText -match 'function\s+(Invoke-FabText|Get-FabLongList|Get-FabItemDefinition|Convert-FixedWidthTableToObjects)') { throw 'Obsolete fab command wrapper or text-table parser still exists.' }
if ($script:InventoryFabCliVersion -ne '1.7.0') { throw 'Reusable.ps1 does not mark fab CLI 1.7.0 compatibility.' }
if (-not (Test-FabSyntaxError -Message "unknown shorthand flag: 'force'")) { throw 'fab syntax-error detection failed.' }
$definition = [pscustomobject]@{ id='m1'; displayName='Model'; workspaceId='w1'; connections=@([pscustomobject]@{ id='c1' }); definition=[pscustomobject]@{ format='TMDL'; parts=@(
    [pscustomobject]@{ path='definition/tables/T.tmdl'; payload="table T`n`tcolumn Id`n`t`tdataType: int64`n`tmeasure Base = SUM(T[Id])`n`tmeasure Derived = [Base] * 2`n`tpartition T = m`n`t`tmode: import`n`t`tsource = Sql.Database(`"server`", `"db`")" },
    [pscustomobject]@{ path='definition/relationships.tmdl'; payload="relationship r1`n`tfromColumn: T.Id`n`ttoColumn: D.Id" }
) } }
$model = ConvertFrom-TmdlSemanticModel -Definition $definition -WorkspaceName 'W'
if ($model.tables.Count -ne 1 -or $model.columns.Count -ne 1 -or $model.measures.Count -ne 2 -or $model.relationships.Count -ne 1) { throw 'TMDL parser count test failed.' }
if (@($model.measures | Where-Object name -eq 'Derived').dependencies -notcontains 'Base') { throw 'Measure dependency test failed.' }
Write-Host 'Reusable tests passed.'
