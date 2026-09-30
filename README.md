# Fabric Inventory

Windows PowerShell 5.1-compatible inventory for the Fabric environment, built around native `fab` CLI commands.

For transferring and running this project on another machine, see [DEPLOYMENT.md](DEPLOYMENT.md).

For a source-control download and execution email, see [EMAIL-DEPLOYMENT-INSTRUCTIONS.md](EMAIL-DEPLOYMENT-INSTRUCTIONS.md).

## Tool priority

1. Native `fab` commands.
2. `fab api` only when no native command can provide the required information.
3. Direct REST only when neither native `fab` nor `fab api` can perform the operation.

Both fallback levels are disabled in `config/inventory.config.json`. The current implementation uses native `fab` commands only.

Compatibility marker: `fab version 1.0.1 (07-2025)`. `Reusable.ps1` is the file to copy into another project when these helpers are needed.

Runtime compatibility was validated with Windows PowerShell `5.1.26100.9444`. PowerShell 7 is optional, not required.

## Individually testable blocks

- `scripts/01-Get-Capacities.ps1`: `fab ls .capacities -l` → `output/capacities.json`
- `scripts/02-Get-Workspaces.ps1`: `fab ls -l` → capacity-linked and unassigned workspaces
- `scripts/03-Get-WorkspaceItems.ps1`: native workspace `fab ls ... -l` → typed items
- `scripts/04-Get-SemanticModels.ps1`: native `fab get ... -q .` → sources, tables, fields, calculated objects, measures, qualified/unique-name measure dependencies, relationships with keys, hierarchies, calculation groups, perspectives, RLS roles, and extraction coverage
- `scripts/05-Get-Reports.ps1`: native report definition → semantic-model connections, normalized page/visual bindings, raw references, and extraction coverage
- `scripts/06-Build-Lineage.ps1`: builds lineage only between distinct objects: data source → semantic model and semantic model → report

Run a block:

```powershell
powershell.exe -NoProfile -File .\scripts\01-Get-Capacities.ps1
```

Scope an item-list test without scanning every workspace:

```powershell
powershell.exe -NoProfile -File .\scripts\03-Get-WorkspaceItems.ps1 -WorkspaceName AdventureDS
```

Run the united flow from a Windows console:

```powershell
.\Invoke-FabricInventory.bat -Stage All
```

Run local parser tests:

```powershell
powershell.exe -NoProfile -File .\tests\Test-Reusable.ps1
```

Run the complete local test suite:

```powershell
powershell.exe -NoProfile -File .\tests\Test-All.ps1
```

Before a long run on a new machine, validate one accessible semantic model with that machine's installed fabcli:

```powershell
powershell.exe -NoProfile -File .\tests\Test-LiveDefinitionAccess.ps1 -Path '<workspace>.Workspace/<model>.SemanticModel'
```

Do not start the complete inventory unless this command ends with `Live definition preflight passed.` and reports non-zero definition parts.

## Coverage notes

- Inventory covers objects visible to the current `fab` identity; it does not claim tenant-admin completeness.
- Definition retrieval can fail for protected/service-managed models or insufficient permission. Failures are retained in JSON instead of silently skipped.
- Measure dependencies use qualified references when available and unique-name resolution otherwise. Ambiguous references are retained explicitly instead of being asserted as dependencies; exact engine dependency metadata would require a separate XMLA block rather than REST.
- Report bindings are normalized by page and visual while the original reference paths are retained for auditability.
- Every semantic-model and report output includes coverage metadata; the document root summarizes complete, partial, and failed extraction counts.
- Credentials are never exported. Data-source connection identity and model source expressions are inventory metadata and can still be sensitive.

## Verified run — 2026-09-28

The complete native-CLI run produced 3 capacities, 114 workspaces, 459 items across 20 item types, 72 semantic models, and 40 reports. Definition extraction succeeded for 68 semantic models and 36 reports. Four service-managed models and their four reports denied definition export; their exact native CLI errors are retained in the JSON outputs. The normalized model output contains 263 tables, 2,852 fields, 187 measures, 172 schema relationships, 90 hierarchies, 1 calculation group, 1 perspective, and 1 RLS role. It resolved 28 measure dependencies and retained 1 ambiguous reference without asserting a false edge. The report output contains 245 normalized visual bindings across 33 reports. Table relationships and measure dependencies remain inside `semantic-models.json`; report field bindings remain inside `reports.json`. `lineage.json` contains 91 relationships between distinct objects: 55 data source → semantic model and 36 semantic model → report.

## Target compatibility validation — 2026-09-30

Definition retrieval now uses exactly `fab get <path> -q .`, with no force option. The Windows PowerShell 5.1 suite verifies the exact argument list and verifies that a fabcli command-syntax error stops after the first affected item instead of repeating the same failure for every item. Run the one-model live preflight on each target machine before a complete inventory.
