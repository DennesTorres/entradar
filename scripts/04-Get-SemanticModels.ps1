param([string]$ItemsPath = (Join-Path $PSScriptRoot '..\output\items.json'), [string]$OutputPath = (Join-Path $PSScriptRoot '..\output\semantic-models.json'))
. (Join-Path $PSScriptRoot '..\Reusable.ps1')
$inventory = Get-Content -Raw -LiteralPath $ItemsPath | ConvertFrom-Json
$targets = @($inventory.items | Where-Object type -eq 'SemanticModel')
$models = @(); $errors = @(); $i = 0
foreach ($target in $targets) {
    $i++; Show-InventoryProgress -Current $i -Total $targets.Count -Message "$($target.workspaceName)/$($target.name)"
    $path = "$($target.workspacePath)/$(ConvertTo-FabPathSegment $target.name).SemanticModel"
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $fabOutput = fab get $path -q . -f --output_format json 2>&1
        $fabExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        if ($fabExitCode -ne 0) { throw "fab get '$path' failed: $($fabOutput -join [Environment]::NewLine)" }
        $fabText = $fabOutput -join [Environment]::NewLine
        $jsonStart = $fabText.IndexOf('{')
        if ($jsonStart -lt 0) { throw "fab get '$path' returned no JSON." }
        $fabResult = $fabText.Substring($jsonStart) | ConvertFrom-Json
        if ($fabResult.status -ne 'Success') { throw "fab get '$path' failed: $($fabResult.result.message)" }
        $definition = @($fabResult.result.data)[0]
        if ($null -eq $definition) { throw "fab get '$path' returned no definition." }
        $models += ConvertFrom-TmdlSemanticModel -Definition $definition -WorkspaceName $target.workspaceName
    }
    catch {
        $ErrorActionPreference = $previousErrorActionPreference
        if (Test-FabSyntaxError -Message $_.Exception.Message) { throw "Stopping semantic-model extraction after a fabcli command-syntax error. No remaining models were attempted. $($_.Exception.Message)" }
        $errors += [pscustomobject]@{ id = $target.id; name = $target.name; workspaceId = $target.workspaceId; workspaceName = $target.workspaceName; sourceMethod = 'fab get (native)'; coverageStatus = 'failed'; error = $_.Exception.Message }
    }
}
Write-Progress -Activity 'Fabric inventory' -Completed
$result = [pscustomobject]@{
    coverageSummary = [pscustomobject]@{ total = $targets.Count; complete = $models.Count; partial = 0; failed = $errors.Count }
    semanticModels = $models
    errors = $errors
}
Write-InventoryJson -InputObject $result -Path $OutputPath
$result
