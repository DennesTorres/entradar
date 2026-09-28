$ErrorActionPreference = 'Stop'
$lineagePath = Join-Path $PSScriptRoot '..\output\lineage.json'
if (-not (Test-Path -LiteralPath $lineagePath)) { throw 'Run scripts\06-Build-Lineage.ps1 before this test.' }
$lineage = Get-Content -Raw -LiteralPath $lineagePath | ConvertFrom-Json -Depth 100
if ($lineage.scope -ne 'betweenObjectsOnly') { throw 'Lineage scope is not betweenObjectsOnly.' }
$internalKinds = @($lineage.edges | Where-Object {
    $_.relationship -in @('tableRelationship','measureDependency','reportObjectReference')
})
if ($internalKinds.Count -gt 0) { throw 'Internal schema or expression lineage leaked into object lineage.' }
$invalidEdges = @($lineage.edges | Where-Object {
    -not $_.upstream.objectType -or -not $_.upstream.id -or -not $_.downstream.objectType -or -not $_.downstream.id
})
if ($invalidEdges.Count -gt 0) { throw 'Object lineage contains an edge without complete object identities.' }
Write-Host 'Lineage separation tests passed.'
