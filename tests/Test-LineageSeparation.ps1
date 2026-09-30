param([string]$LineagePath = (Join-Path $PSScriptRoot '..\output\lineage.json'))
$ErrorActionPreference = 'Stop'
$lineagePath = $LineagePath
$fixtureFolder = $null
if (-not (Test-Path -LiteralPath $lineagePath)) {
    . (Join-Path $PSScriptRoot '..\Reusable.ps1')
    $fixtureFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("fabric-inventory-lineage-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureFolder | Out-Null
    $modelsPath = Join-Path $fixtureFolder 'semantic-models.json'
    $reportsPath = Join-Path $fixtureFolder 'reports.json'
    $lineagePath = Join-Path $fixtureFolder 'lineage.json'
    Write-InventoryJson -Path $modelsPath -InputObject ([pscustomobject]@{
        semanticModels = @([pscustomobject]@{
            id = 'model-1'; name = 'Model'; workspaceId = 'workspace-1'; workspaceName = 'Workspace'
            dataSources = @([pscustomobject]@{ id = 'source-1'; connectionDetails = [pscustomobject]@{ type = 'SQL'; path = 'server;database' }; connectivityType = 'Import' })
            relationships = @([pscustomobject]@{ name = 'schema-relationship' })
            measures = @([pscustomobject]@{ name = 'Derived'; dependencies = @('Base') })
        })
        errors = @()
    })
    Write-InventoryJson -Path $reportsPath -InputObject ([pscustomobject]@{
        reports = @([pscustomobject]@{
            id = 'report-1'; name = 'Report'; workspaceId = 'workspace-1'; workspaceName = 'Workspace'
            references = @([pscustomobject]@{ path = 'definition.pbir.datasetReference.byConnection.connectionString'; value = 'Data Source=x;semanticmodelid=model-1' })
            visualBindings = @([pscustomobject]@{ pageId = 'page-1'; visualId = 'visual-1'; measures = @('Base') })
        })
        errors = @()
    })
    & (Join-Path $PSScriptRoot '..\scripts\06-Build-Lineage.ps1') -ModelsPath $modelsPath -ReportsPath $reportsPath -OutputPath $lineagePath | Out-Null
}
$lineage = Get-Content -Raw -LiteralPath $lineagePath | ConvertFrom-Json
if ($lineage.scope -ne 'betweenObjectsOnly') { throw 'Lineage scope is not betweenObjectsOnly.' }
$internalKinds = @($lineage.edges | Where-Object {
    $_.relationship -in @('tableRelationship','measureDependency','reportObjectReference')
})
if ($internalKinds.Count -gt 0) { throw 'Internal schema or expression lineage leaked into object lineage.' }
$invalidEdges = @($lineage.edges | Where-Object {
    -not $_.upstream.objectType -or -not $_.upstream.id -or -not $_.downstream.objectType -or -not $_.downstream.id
})
if ($invalidEdges.Count -gt 0) { throw 'Object lineage contains an edge without complete object identities.' }
if ($fixtureFolder) { Remove-Item -LiteralPath $fixtureFolder -Recurse -Force }
Write-Host 'Lineage separation tests passed.'
