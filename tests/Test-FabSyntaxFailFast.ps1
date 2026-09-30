$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Reusable.ps1')

$fixtureFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("fabric-inventory-fail-fast-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureFolder | Out-Null
$itemsPath = Join-Path $fixtureFolder 'items.json'
$outputPath = Join-Path $fixtureFolder 'semantic-models.json'
Write-InventoryJson -Path $itemsPath -InputObject ([pscustomobject]@{
    items = @(
        [pscustomobject]@{ id = 'model-1'; name = 'Model1'; type = 'SemanticModel'; workspaceId = 'workspace-1'; workspaceName = 'Workspace'; workspacePath = 'Workspace.Workspace' },
        [pscustomobject]@{ id = 'model-2'; name = 'Model2'; type = 'SemanticModel'; workspaceId = 'workspace-1'; workspaceName = 'Workspace'; workspacePath = 'Workspace.Workspace' }
    )
    errors = @()
})

$global:FabDefinitionCallCount = 0
function fab {
    if ($args[0] -eq 'get' -and $args[1] -eq '--help') { $global:LASTEXITCODE = 0; 'Flags: -q, --query Query'; return }
    $global:FabDefinitionCallCount++
    $global:LASTEXITCODE = 1
    "unknown shorthand flag: 'query'"
}

$caught = $null
try { & (Join-Path $PSScriptRoot '..\scripts\04-Get-SemanticModels.ps1') -ItemsPath $itemsPath -OutputPath $outputPath | Out-Null }
catch { $caught = $_.Exception.Message }
Remove-Item -Path Function:\fab
Remove-Item -LiteralPath $fixtureFolder -Recurse -Force

if (-not $caught -or $caught -notmatch 'Stopping semantic-model extraction') { throw 'Semantic-model extraction did not expose the syntax error.' }
if ($global:FabDefinitionCallCount -ne 1) { throw "Syntax failure was repeated $global:FabDefinitionCallCount times instead of stopping after the first model." }
Write-Host 'fab syntax fail-fast test passed.'
