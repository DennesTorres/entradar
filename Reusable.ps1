# Reusable helpers copied forward from fabCLIPermissions and extended for Inventory.
# Fabric CLI compatibility marker: fab version 1.0.1 (07-2025)
$script:InventoryFabCliVersion = '1.0.1 (07-2025)'

function Convert-FixedWidthTableToObjects {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][string[]]$TableText)
    begin { $lines = @() }
    process { if ($null -ne $_) { $lines += $_.ToString() } }
    end {
        $lines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -lt 2) { return @() }
        $header = $lines[0]
        $separator = $lines[1]
        if ($separator -notmatch '^-{3,}') { throw 'Expected fab long-list output. Use -l.' }
        $matches = [regex]::Matches($header, '\S+')
        $columns = for ($index = 0; $index -lt $matches.Count; $index++) {
            $start = $matches[$index].Index
            $end = if ($index + 1 -lt $matches.Count) { $matches[$index + 1].Index } else { $separator.Length }
            [pscustomobject]@{ Name = $matches[$index].Value; Start = $start; Length = $end - $start }
        }
        if ($lines.Count -eq 2) { return @() }
        foreach ($line in $lines[2..($lines.Count - 1)]) {
            $record = [ordered]@{}
            foreach ($column in $columns) {
                $value = if ($column.Start -ge $line.Length) { '' } else { $line.Substring($column.Start, [Math]::Min($column.Length, $line.Length - $column.Start)).Trim() }
                $record[$column.Name] = $value
            }
            [pscustomobject]$record
        }
    }
}

function Show-InventoryProgress {
    param([int]$Current, [int]$Total, [string]$Message)
    $percent = if ($Total -le 0) { 100 } else { [Math]::Round(($Current / $Total) * 100) }
    Write-Progress -Activity 'Fabric inventory' -Status "$percent% - $Message" -PercentComplete $percent
}

function Invoke-FabText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& fab @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) { throw "fab $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    $output
}

function Get-FabLongList {
    param([string]$Path)
    $arguments = @('ls')
    if ($Path) { $arguments += $Path }
    $arguments += '-l'
    @(Invoke-FabText -Arguments $arguments | Convert-FixedWidthTableToObjects)
}

function Get-FabItemDefinition {
    param([Parameter(Mandatory)][string]$Path)
    $lines = @(Invoke-FabText -Arguments @('get', $Path, '-q', '.', '-f'))
    $start = 0
    while ($start -lt $lines.Count -and $lines[$start].TrimStart() -notmatch '^[{[]') { $start++ }
    if ($start -ge $lines.Count) { throw "fab get returned no JSON for $Path" }
    ($lines[$start..($lines.Count - 1)] -join [Environment]::NewLine) | ConvertFrom-Json
}

function Write-InventoryJson {
    param([Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $json = $InputObject | ConvertTo-Json -Depth 100
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8WithoutBom)
}

function Get-InventoryConfig {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-DefinitionText {
    param([Parameter(Mandatory)]$Part)
    if ($Part.payload -is [string]) { return $Part.payload }
    $Part.payload | ConvertTo-Json -Depth 100 -Compress
}

function ConvertFrom-TmdlName {
    param([string]$Name)
    $value = $Name.Trim()
    if ($value.StartsWith("'") -and $value.EndsWith("'")) { return $value.Substring(1, $value.Length - 2).Replace("''", "'") }
    $value
}

function ConvertTo-FabPathSegment {
    param([Parameter(Mandatory)][string]$Name)
    $Name.Replace('/', '\/')
}

function Get-TmdlBlocks {
    param([string]$Text, [string]$Kind)
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^`t$Kind\s+(.+)$") {
            $start = $i
            $i++
            while ($i -lt $lines.Count -and $lines[$i] -notmatch "^`t\S") { $i++ }
            [pscustomobject]@{ Declaration = $lines[$start].Substring(1); Lines = @($lines[$start..($i - 1)]); Text = ($lines[$start..($i - 1)] -join "`n") }
            $i--
        }
    }
}

function Get-DeclarationParts {
    param([string]$Declaration, [string]$Kind)
    $rest = $Declaration.Substring($Kind.Length).Trim()
    $equals = $rest.IndexOf(' = ')
    if ($equals -ge 0) {
        [pscustomobject]@{ Name = ConvertFrom-TmdlName $rest.Substring(0, $equals); Expression = $rest.Substring($equals + 3); IsCalculated = $true }
    } else {
        [pscustomobject]@{ Name = ConvertFrom-TmdlName $rest; Expression = $null; IsCalculated = $false }
    }
}

function ConvertFrom-TmdlSemanticModel {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)][string]$WorkspaceName)
    $tables = @()
    $measures = @()
    $columns = @()
    $partitions = @()
    foreach ($part in @($Definition.definition.parts | Where-Object { $_.path -like 'definition/tables/*.tmdl' })) {
        $text = Get-DefinitionText $part
        $tableMatch = [regex]::Match($text, '(?m)^table\s+(.+)$')
        if (-not $tableMatch.Success) { continue }
        $tableName = ConvertFrom-TmdlName $tableMatch.Groups[1].Value
        $tablePartitions = @()
        foreach ($block in @(Get-TmdlBlocks -Text $text -Kind 'partition')) {
            $parts = Get-DeclarationParts -Declaration $block.Declaration -Kind 'partition'
            $sourceType = if ($block.Declaration -match '=\s*(\w+)') { $Matches[1] } else { 'unknown' }
            $sourceMatch = [regex]::Match($block.Text, '(?ms)^\t\tsource\s*=\s*(.+)$')
            $partition = [pscustomobject]@{ name = $parts.Name; sourceType = $sourceType; expression = if ($sourceMatch.Success) { $sourceMatch.Groups[1].Value.Trim() } else { $null } }
            $tablePartitions += $partition
            $partitions += [pscustomobject]@{ table = $tableName; name = $partition.name; sourceType = $partition.sourceType; expression = $partition.expression }
        }
        foreach ($block in @(Get-TmdlBlocks -Text $text -Kind 'column')) {
            $parts = Get-DeclarationParts -Declaration $block.Declaration -Kind 'column'
            $columns += [pscustomobject]@{ table = $tableName; name = $parts.Name; kind = if ($parts.IsCalculated) { 'calculated' } else { 'source' }; expression = $parts.Expression; dataType = if ($block.Text -match '(?m)^\t\tdataType:\s*(.+)$') { $Matches[1].Trim() } else { $null }; sourceColumn = if ($block.Text -match '(?m)^\t\tsourceColumn:\s*(.+)$') { $Matches[1].Trim() } else { $null }; isHidden = ($block.Text -match '(?m)^\t\tisHidden\s*$') }
        }
        foreach ($block in @(Get-TmdlBlocks -Text $text -Kind 'measure')) {
            $parts = Get-DeclarationParts -Declaration $block.Declaration -Kind 'measure'
            $expression = $parts.Expression
            if ([string]::IsNullOrWhiteSpace($expression)) {
                $expressionLines = @($block.Lines | Select-Object -Skip 1 | Where-Object { $_ -notmatch '^\t\t(formatString|lineageTag|displayFolder|description|annotation):?' })
                $expression = ($expressionLines -join "`n").Trim()
            }
            $measure = [pscustomobject]@{ table = $tableName; name = $parts.Name; expression = $expression; dependencies = @() }
            $measures += $measure
        }
        $tables += [pscustomobject]@{ name = $tableName; kind = if ($tablePartitions.sourceType -contains 'calculated') { 'calculated' } else { 'regular' }; partitions = $tablePartitions }
    }
    $measureNames = @($measures.name)
    foreach ($measure in $measures) {
        $refs = [regex]::Matches([string]$measure.expression, '\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $measure.dependencies = @($refs | Where-Object { $_ -in $measureNames -and $_ -ne $measure.name })
    }
    $relationships = @()
    $relationshipPart = @($Definition.definition.parts | Where-Object { $_.path -eq 'definition/relationships.tmdl' }) | Select-Object -First 1
    if ($relationshipPart) {
        $text = Get-DefinitionText $relationshipPart
        $blocks = [regex]::Split($text, '(?m)(?=^relationship\s+)') | Where-Object { $_ -match '^relationship\s+' }
        foreach ($block in $blocks) {
            $relationships += [pscustomobject]@{
                name = if ($block -match '(?m)^relationship\s+(.+)$') { $Matches[1].Trim() } else { $null }
                fromColumn = if ($block -match '(?m)^\tfromColumn:\s*(.+)$') { $Matches[1].Trim() } else { $null }
                toColumn = if ($block -match '(?m)^\ttoColumn:\s*(.+)$') { $Matches[1].Trim() } else { $null }
                fromCardinality = if ($block -match '(?m)^\tfromCardinality:\s*(.+)$') { $Matches[1].Trim() } else { 'many' }
                toCardinality = if ($block -match '(?m)^\ttoCardinality:\s*(.+)$') { $Matches[1].Trim() } else { 'one' }
                crossFilteringBehavior = if ($block -match '(?m)^\tcrossFilteringBehavior:\s*(.+)$') { $Matches[1].Trim() } else { 'oneDirection' }
                isActive = -not ($block -match '(?m)^\tisActive:\s*false')
            }
        }
    }
    [pscustomobject]@{
        id = $Definition.id; name = $Definition.displayName; workspaceId = $Definition.workspaceId; workspaceName = $WorkspaceName
        sourceMethod = 'fab get (native)'; format = $Definition.definition.format
        dataSources = @($Definition.connections); tables = $tables; columns = $columns; measures = $measures; relationships = $relationships
        coverage = [pscustomobject]@{ definition = 'complete'; measureDependencyMethod = 'DAX reference resolution from exported TMDL'; caveat = 'Ambiguous column/measure names are resolved only when the referenced name matches a known measure.' }
    }
}

function Get-JsonPropertyReferences {
    param($Node, [string]$Context = '')
    $results = @()
    if ($null -eq $Node) { return $results }
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $next = if ($Context) { "$Context.$key" } else { [string]$key }
            $results += Get-JsonPropertyReferences -Node $Node[$key] -Context $next
        }
    } elseif ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $next = if ($Context) { "$Context.$($property.Name)" } else { $property.Name }
            if ($property.Name -in @('Entity','Property','Measure','datasetId','datasetWorkspaceId','semanticModelId','connectionString')) {
                $results += [pscustomobject]@{ path = $next; value = $property.Value }
            }
            $results += Get-JsonPropertyReferences -Node $property.Value -Context $next
        }
    } elseif ($Node -is [string] -and $Node.TrimStart() -match '^[{[]') {
        try { $results += Get-JsonPropertyReferences -Node ($Node | ConvertFrom-Json) -Context $Context } catch { }
    } elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        $index = 0
        foreach ($item in $Node) { $results += Get-JsonPropertyReferences -Node $item -Context "$Context[$index]"; $index++ }
    }
    $results
}

function ConvertFrom-PbirReport {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)][string]$WorkspaceName)
    $references = @()
    foreach ($part in @($Definition.definition.parts | Where-Object { $_.path -match '(definition\.pbir|visual\.json|report\.json)$' })) {
        try {
            $json = (Get-DefinitionText $part) | ConvertFrom-Json
            $references += Get-JsonPropertyReferences -Node $json -Context $part.path
        } catch { }
    }
    [pscustomobject]@{ id = $Definition.id; name = $Definition.displayName; workspaceId = $Definition.workspaceId; workspaceName = $WorkspaceName; sourceMethod = 'fab get (native)'; format = $Definition.definition.format; connections = @($Definition.connections); references = @($references | Sort-Object path, value -Unique) }
}
