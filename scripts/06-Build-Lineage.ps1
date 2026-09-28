param(
    [string]$ModelsPath = (Join-Path $PSScriptRoot '..\output\semantic-models.json'),
    [string]$ReportsPath = (Join-Path $PSScriptRoot '..\output\reports.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\output\lineage.json')
)

. (Join-Path $PSScriptRoot '..\Reusable.ps1')

function ConvertFrom-ConnectionString {
    param([string]$ConnectionString)
    $values = @{}
    foreach ($part in @($ConnectionString -split ';')) {
        $equals = $part.IndexOf('=')
        if ($equals -le 0) { continue }
        $name = $part.Substring(0, $equals).Trim().ToLowerInvariant()
        $value = $part.Substring($equals + 1).Trim().Trim('"')
        $values[$name] = $value
    }
    $values
}

$modelsDocument = Get-Content -Raw -LiteralPath $ModelsPath | ConvertFrom-Json
$reportsDocument = Get-Content -Raw -LiteralPath $ReportsPath | ConvertFrom-Json
$models = @($modelsDocument.semanticModels)
$reports = @($reportsDocument.reports)
$edges = @()

# Object lineage: external/Fabric data source -> semantic model.
foreach ($model in $models) {
    foreach ($dataSource in @($model.dataSources)) {
        $sourceId = if ($dataSource.id) { $dataSource.id } else { "$($dataSource.connectionDetails.type)|$($dataSource.connectionDetails.path)" }
        $edges += [pscustomobject]@{
            relationship = 'semanticModelUsesDataSource'
            upstream = [pscustomobject]@{
                objectType = 'DataSource'
                id = $sourceId
                name = $dataSource.connectionDetails.path
                dataSourceType = $dataSource.connectionDetails.type
                connectivityType = $dataSource.connectivityType
            }
            downstream = [pscustomobject]@{
                objectType = 'SemanticModel'
                id = $model.id
                name = $model.name
                workspaceId = $model.workspaceId
                workspaceName = $model.workspaceName
            }
            sourceMethod = 'semantic model connection metadata from native fab get'
        }
    }
}

# Object lineage: semantic model -> report. Report field bindings stay in reports.json.
foreach ($report in $reports) {
    $connectionStrings = @($report.references | Where-Object path -like '*connectionString' | Select-Object -ExpandProperty value -Unique)
    foreach ($connectionString in $connectionStrings) {
        $values = ConvertFrom-ConnectionString -ConnectionString $connectionString
        $semanticModelId = $values['semanticmodelid']
        if ([string]::IsNullOrWhiteSpace($semanticModelId)) { continue }
        $model = @($models | Where-Object id -eq $semanticModelId) | Select-Object -First 1
        $edges += [pscustomobject]@{
            relationship = 'reportUsesSemanticModel'
            upstream = [pscustomobject]@{
                objectType = 'SemanticModel'
                id = $semanticModelId
                name = if ($model) { $model.name } else { $values['initial catalog'] }
                workspaceId = if ($model) { $model.workspaceId } else { $null }
                workspaceName = if ($model) { $model.workspaceName } else { $null }
            }
            downstream = [pscustomobject]@{
                objectType = 'Report'
                id = $report.id
                name = $report.name
                workspaceId = $report.workspaceId
                workspaceName = $report.workspaceName
            }
            sourceMethod = 'report semantic-model connection from native fab get'
        }
    }
}

$uniqueEdges = @($edges | Group-Object {
    "$($_.relationship)|$($_.upstream.objectType)|$($_.upstream.id)|$($_.downstream.objectType)|$($_.downstream.id)"
} | ForEach-Object { $_.Group[0] })

$result = [pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    scope = 'betweenObjectsOnly'
    edges = $uniqueEdges
    excludedInternalStructures = @(
        'table relationships (semantic-model schema in semantic-models.json)',
        'measure dependencies (internal semantic-model lineage in semantic-models.json)',
        'report field and measure bindings (internal report metadata in reports.json)'
    )
    semanticModelErrors = @($modelsDocument.errors)
    reportErrors = @($reportsDocument.errors)
}

Write-InventoryJson -InputObject $result -Path $OutputPath
$result
