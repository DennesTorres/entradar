$ErrorActionPreference = 'Stop'
$tests = @(
    'Test-Reusable.ps1',
    'Test-GovernanceMetadata.ps1',
    'Test-LineageSeparation.ps1'
)
foreach ($test in $tests) {
    & (Join-Path $PSScriptRoot $test)
}
Write-Host 'All inventory tests passed.'
