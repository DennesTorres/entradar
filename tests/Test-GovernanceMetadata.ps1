$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')

$tablePayload = @"
table Sales
	column Amount
		dataType: decimal
	measure Base = SUM(Sales[Amount])
	measure Derived = [Base] * 2 + "[Ignored inside a string]"
	hierarchy Calendar
		level Year = Sales[Year]
		level Month = Sales[Month]
	calculationGroup
		precedence: 10
		calculationItem Current = SELECTEDMEASURE()
	partition Sales = m
		mode: import
		source = Sql.Database("server", "db")
"@
$rolePayload = @"
role Sales Reader
	modelPermission: read
	tablePermission Sales
		filterExpression = Sales[Region] = "EU"
"@
$perspectivePayload = @"
perspective Executive
	perspectiveTable Sales
"@
$definition = [pscustomobject]@{
    id = 'm1'; displayName = 'Model'; workspaceId = 'w1'; connections = @()
    definition = [pscustomobject]@{ format = 'TMDL'; parts = @(
        [pscustomobject]@{ path = 'definition/tables/Sales.tmdl'; payload = $tablePayload },
        [pscustomobject]@{ path = 'definition/perspectives/Executive.tmdl'; payload = $perspectivePayload },
        [pscustomobject]@{ path = 'definition/roles/Sales Reader.tmdl'; payload = $rolePayload }
    ) }
}
$model = ConvertFrom-TmdlSemanticModel -Definition $definition -WorkspaceName 'W'
if ($model.hierarchies.Count -ne 1 -or $model.hierarchies[0].levels.Count -ne 2) { throw 'Hierarchy extraction test failed.' }
if ($model.calculationGroups.Count -ne 1 -or $model.calculationGroups[0].items.Count -ne 1) { throw 'Calculation-group extraction test failed.' }
if ($model.perspectives.Count -ne 1 -or $model.perspectives[0].tables -notcontains 'Sales') { throw 'Perspective extraction test failed.' }
if ($model.roles.Count -ne 1 -or $model.roles[0].tablePermissions[0].filterExpression -notmatch 'Region') { throw 'RLS extraction test failed.' }
$derived = @($model.measures | Where-Object name -eq 'Derived')[0]
if ($derived.dependencies -notcontains 'Base' -or $derived.dependencies -contains 'Ignored inside a string') { throw 'DAX dependency resolution test failed.' }
if ($model.coverage.status -ne 'complete' -or $model.coverage.capturedCategories -notcontains 'roles') { throw 'Semantic-model coverage metadata test failed.' }

$emptyDefinition = [pscustomobject]@{ id = 'empty'; displayName = 'Empty'; workspaceId = 'w1'; connections = @(); definition = [pscustomobject]@{ format = 'TMDL'; parts = @() } }
$emptyModel = ConvertFrom-TmdlSemanticModel -Definition $emptyDefinition -WorkspaceName 'W'
if ($emptyModel.tables.Count -ne 0 -or $emptyModel.coverage.status -ne 'complete') { throw 'Empty semantic-model definition test failed.' }

$reportDefinition = [pscustomobject]@{
    id = 'r1'; displayName = 'Report'; workspaceId = 'w1'; connections = @()
    definition = [pscustomobject]@{ format = 'PBIR-Legacy'; parts = @(
        [pscustomobject]@{ path = 'definition.pbir'; payload = '{"datasetReference":{"byConnection":{"connectionString":"Data Source=x;semanticmodelid=m1"}}}' },
        [pscustomobject]@{ path = 'report.json'; payload = '{"sections":[{"visualContainers":[{"config":{"singleVisual":{"prototypeQuery":{"From":[{"Entity":"Sales"}],"Select":[{"Column":{"Property":"Amount"}},{"Measure":{"Property":"Base"}}]}}}}]}]}' }
    ) }
}
$report = ConvertFrom-PbirReport -Definition $reportDefinition -WorkspaceName 'W'
if ($report.semanticModelReferences.Count -ne 1 -or $report.semanticModelReferences[0].semanticModelId -ne 'm1') { throw 'Report semantic-model reference test failed.' }
if ($report.visualBindings.Count -ne 1 -or $report.visualBindings[0].columns -notcontains 'Amount' -or $report.visualBindings[0].measures -notcontains 'Base') { throw 'Normalized report binding test failed.' }
if ($report.coverage.status -ne 'complete' -or $report.coverage.visualCount -ne 1) { throw 'Report coverage metadata test failed.' }

Write-Host 'Governance metadata tests passed.'
