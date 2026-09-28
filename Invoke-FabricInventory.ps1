[CmdletBinding()]
param([ValidateSet('All','Capacities','Workspaces','Items','SemanticModels','Reports','Lineage')][string]$Stage = 'All')
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $PSScriptRoot 'scripts'
if ($Stage -in @('All','Capacities')) { & (Join-Path $scripts '01-Get-Capacities.ps1') | Out-Null }
if ($Stage -in @('All','Workspaces')) { & (Join-Path $scripts '02-Get-Workspaces.ps1') | Out-Null }
if ($Stage -in @('All','Items')) { & (Join-Path $scripts '03-Get-WorkspaceItems.ps1') | Out-Null }
if ($Stage -in @('All','SemanticModels')) { & (Join-Path $scripts '04-Get-SemanticModels.ps1') | Out-Null }
if ($Stage -in @('All','Reports')) { & (Join-Path $scripts '05-Get-Reports.ps1') | Out-Null }
if ($Stage -in @('All','Lineage')) { & (Join-Path $scripts '06-Build-Lineage.ps1') | Out-Null }
Write-Host "Inventory stage '$Stage' completed. JSON files are in $(Join-Path $PSScriptRoot 'output')."
