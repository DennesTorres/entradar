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
    # Use the long option because some fabcli builds reject the -f shorthand.
    $lines = @(Invoke-FabText -Arguments @('get', $Path, '-q', '.', '--force'))
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

function Remove-DaxNonCodeText {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return '' }
    $value = [regex]::Replace($Expression, '(?s)/\*.*?\*/', ' ')
    $value = [regex]::Replace($value, '(?m)//.*$', ' ')
    $value = [regex]::Replace($value, '"(?:""|[^"])*"', ' ')
    $value
}

function Resolve-DaxMeasureDependencies {
    param([Parameter(Mandatory)]$Measure, [Parameter(Mandatory)][object[]]$AllMeasures)
    $expression = Remove-DaxNonCodeText ([string]$Measure.expression)
    $resolved = @()
    $ambiguous = @()
    $qualifiedSpans = @()

    $qualifiedPattern = "(?:(?:'(?<quoted>(?:''|[^'])+)')|(?<plain>[A-Za-z_][A-Za-z0-9_ ]*))\s*\[(?<name>[^\]]+)\]"
    foreach ($match in [regex]::Matches($expression, $qualifiedPattern)) {
        $tableName = if ($match.Groups['quoted'].Success) { $match.Groups['quoted'].Value.Replace("''", "'") } else { $match.Groups['plain'].Value.Trim() }
        $measureName = $match.Groups['name'].Value
        $candidates = @($AllMeasures | Where-Object { $_.table -eq $tableName -and $_.name -eq $measureName })
        if ($candidates.Count -eq 1 -and -not ($candidates[0].table -eq $Measure.table -and $candidates[0].name -eq $Measure.name)) {
            $resolved += [pscustomobject]@{ table = $candidates[0].table; measure = $candidates[0].name; reference = $match.Value; resolution = 'qualified' }
        }
        $qualifiedSpans += [pscustomobject]@{ index = $match.Index; length = $match.Length }
    }

    foreach ($match in [regex]::Matches($expression, '(?<![A-Za-z0-9_''\]])\[(?<name>[^\]]+)\]')) {
        $insideQualifiedReference = @($qualifiedSpans | Where-Object { $match.Index -ge $_.index -and $match.Index -lt ($_.index + $_.length) }).Count -gt 0
        if ($insideQualifiedReference) { continue }
        $measureName = $match.Groups['name'].Value
        $candidates = @($AllMeasures | Where-Object name -eq $measureName)
        if ($candidates.Count -eq 1) {
            if (-not ($candidates[0].table -eq $Measure.table -and $candidates[0].name -eq $Measure.name)) {
                $resolved += [pscustomobject]@{ table = $candidates[0].table; measure = $candidates[0].name; reference = $match.Value; resolution = 'uniqueName' }
            }
        } elseif ($candidates.Count -gt 1) {
            $ambiguous += [pscustomobject]@{ reference = $match.Value; candidateMeasures = @($candidates | ForEach-Object { "$($_.table)[$($_.name)]" }) }
        }
    }

    [pscustomobject]@{
        resolved = @($resolved | Sort-Object table, measure -Unique)
        ambiguous = @($ambiguous | Sort-Object reference -Unique)
    }
}

function Get-TmdlGovernanceMetadata {
    param([Parameter(Mandatory)]$Definition)
    $hierarchies = @()
    $calculationGroups = @()
    foreach ($part in @($Definition.definition.parts | Where-Object { $_.path -like 'definition/tables/*.tmdl' })) {
        $text = Get-DefinitionText $part
        $tableMatch = [regex]::Match($text, '(?m)^table\s+(.+)$')
        if (-not $tableMatch.Success) { continue }
        $tableName = ConvertFrom-TmdlName $tableMatch.Groups[1].Value
        foreach ($block in @(Get-TmdlBlocks -Text $text -Kind 'hierarchy')) {
            $parts = Get-DeclarationParts -Declaration $block.Declaration -Kind 'hierarchy'
            $levels = @()
            foreach ($levelMatch in [regex]::Matches($block.Text, "(?m)^\t\tlevel\s+(.+?)(?:\s*=\s*(.+))?$")) {
                $levels += [pscustomobject]@{ name = ConvertFrom-TmdlName $levelMatch.Groups[1].Value.Trim(); column = if ($levelMatch.Groups[2].Success) { $levelMatch.Groups[2].Value.Trim() } else { $null } }
            }
            $hierarchies += [pscustomobject]@{ table = $tableName; name = $parts.Name; levels = $levels }
        }
        if ($text -match '(?m)^\tcalculationGroup(?:\s|$)') {
            $items = @()
            foreach ($itemMatch in [regex]::Matches($text, "(?m)^\t\tcalculationItem\s+(.+?)(?:\s+=\s*(.*))?$")) {
                $items += [pscustomobject]@{ name = ConvertFrom-TmdlName $itemMatch.Groups[1].Value.Trim(); expression = if ($itemMatch.Groups[2].Success) { $itemMatch.Groups[2].Value.Trim() } else { $null } }
            }
            $calculationGroups += [pscustomobject]@{ table = $tableName; precedence = if ($text -match '(?m)^\t\tprecedence:\s*(\d+)') { [int]$Matches[1] } else { $null }; items = $items }
        }
    }

    $perspectives = @()
    foreach ($part in @($Definition.definition.parts | Where-Object { $_.path -like 'definition/perspectives/*.tmdl' })) {
        $text = Get-DefinitionText $part
        $nameMatch = [regex]::Match($text, '(?m)^perspective\s+(.+)$')
        $perspectives += [pscustomobject]@{
            name = if ($nameMatch.Success) { ConvertFrom-TmdlName $nameMatch.Groups[1].Value } else { [System.IO.Path]::GetFileNameWithoutExtension($part.path) }
            tables = @([regex]::Matches($text, '(?m)^\tperspectiveTable\s+(.+)$') | ForEach-Object { ConvertFrom-TmdlName $_.Groups[1].Value } | Sort-Object -Unique)
        }
    }

    $roles = @()
    foreach ($part in @($Definition.definition.parts | Where-Object { $_.path -like 'definition/roles/*.tmdl' })) {
        $text = Get-DefinitionText $part
        $nameMatch = [regex]::Match($text, '(?m)^role\s+(.+)$')
        $permissions = @()
        $permissionMatches = [regex]::Matches($text, '(?ms)^\ttablePermission\s+(.+?)\r?\n(?<body>(?:\t\t.*(?:\r?\n|$))*)')
        foreach ($permissionMatch in $permissionMatches) {
            $body = $permissionMatch.Groups['body'].Value
            $filterMatch = [regex]::Match($body, '(?ms)^\t\tfilterExpression\s*=\s*(.+?)(?=^\t\t\w|\z)')
            $permissions += [pscustomobject]@{ table = ConvertFrom-TmdlName $permissionMatch.Groups[1].Value.Trim(); filterExpression = if ($filterMatch.Success) { $filterMatch.Groups[1].Value.Trim() } else { $null } }
        }
        $roles += [pscustomobject]@{
            name = if ($nameMatch.Success) { ConvertFrom-TmdlName $nameMatch.Groups[1].Value } else { [System.IO.Path]::GetFileNameWithoutExtension($part.path) }
            modelPermission = if ($text -match '(?m)^\tmodelPermission:\s*(.+)$') { $Matches[1].Trim() } else { $null }
            tablePermissions = $permissions
        }
    }
    [pscustomobject]@{ hierarchies = $hierarchies; calculationGroups = $calculationGroups; perspectives = $perspectives; roles = $roles }
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
    foreach ($measure in $measures) {
        $dependencyResult = Resolve-DaxMeasureDependencies -Measure $measure -AllMeasures $measures
        $measure.dependencies = @($dependencyResult.resolved | ForEach-Object measure | Sort-Object -Unique)
        $measure | Add-Member -NotePropertyName dependencyDetails -NotePropertyValue @($dependencyResult.resolved)
        $measure | Add-Member -NotePropertyName ambiguousDependencies -NotePropertyValue @($dependencyResult.ambiguous)
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
    $governance = Get-TmdlGovernanceMetadata -Definition $Definition
    [pscustomobject]@{
        id = $Definition.id; name = $Definition.displayName; workspaceId = $Definition.workspaceId; workspaceName = $WorkspaceName
        sourceMethod = 'fab get (native)'; format = $Definition.definition.format
        dataSources = @($Definition.connections); tables = $tables; columns = $columns; measures = $measures; relationships = $relationships
        hierarchies = @($governance.hierarchies); calculationGroups = @($governance.calculationGroups); perspectives = @($governance.perspectives); roles = @($governance.roles)
        coverage = [pscustomobject]@{
            status = 'complete'; definition = 'complete'
            capturedCategories = @('dataSources','tables','columns','measures','measureDependencies','relationships','hierarchies','calculationGroups','perspectives','roles')
            measureDependencyMethod = 'qualified and unique-name DAX reference resolution from exported TMDL'
            ambiguousMeasureReferences = @($measures.ambiguousDependencies).Count
        }
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
    $references = @($references | Sort-Object path, value -Unique)
    $visualGroups = @{}
    foreach ($reference in $references) {
        $pageId = $null; $visualId = $null
        if ($reference.path -match 'report\.json\.sections\[(\d+)\]\.visualContainers\[(\d+)\]') { $pageId = "section-$($Matches[1])"; $visualId = "visual-$($Matches[2])" }
        elseif ($reference.path -match 'definition/pages/([^/]+)/visuals/([^/]+)/visual\.json') { $pageId = $Matches[1]; $visualId = $Matches[2] }
        if (-not $pageId -or -not $visualId) { continue }
        $key = "$pageId|$visualId"
        if (-not $visualGroups.ContainsKey($key)) { $visualGroups[$key] = [pscustomobject]@{ pageId = $pageId; visualId = $visualId; entities = @(); columns = @(); measures = @(); hierarchies = @(); sourcePaths = @() } }
        $binding = $visualGroups[$key]
        if ($reference.path -match '\.Entity$' -and $reference.value -is [string]) { $binding.entities += $reference.value }
        elseif ($reference.path -match '\.Measure\.Property$' -and $reference.value -is [string]) { $binding.measures += $reference.value }
        elseif ($reference.path -match '\.Column\.Property$' -and $reference.value -is [string]) { $binding.columns += $reference.value }
        elseif ($reference.path -match '\.Hierarchy(?:Level)?\.Property$' -and $reference.value -is [string]) { $binding.hierarchies += $reference.value }
        $binding.sourcePaths += $reference.path
    }
    $visualBindings = @($visualGroups.Values | ForEach-Object {
        [pscustomobject]@{ pageId = $_.pageId; visualId = $_.visualId; entities = @($_.entities | Sort-Object -Unique); columns = @($_.columns | Sort-Object -Unique); measures = @($_.measures | Sort-Object -Unique); hierarchies = @($_.hierarchies | Sort-Object -Unique); sourcePaths = @($_.sourcePaths | Sort-Object -Unique) }
    } | Sort-Object pageId, visualId)
    $semanticModelReferences = @($references | Where-Object path -like '*connectionString' | ForEach-Object {
        $idMatch = [regex]::Match([string]$_.value, '(?i)(?:^|;)semanticmodelid=([^;]+)')
        if ($idMatch.Success) { [pscustomobject]@{ semanticModelId = $idMatch.Groups[1].Value; connectionString = $_.value } }
    } | Sort-Object semanticModelId -Unique)
    [pscustomobject]@{
        id = $Definition.id; name = $Definition.displayName; workspaceId = $Definition.workspaceId; workspaceName = $WorkspaceName
        sourceMethod = 'fab get (native)'; format = $Definition.definition.format; connections = @($Definition.connections)
        semanticModelReferences = $semanticModelReferences; visualBindings = $visualBindings; references = $references
        coverage = [pscustomobject]@{ status = 'complete'; definition = 'complete'; capturedCategories = @('semanticModelReferences','visualBindings','rawReferences'); visualCount = $visualBindings.Count }
    }
}
