# Fabric Inventory

PowerShell inventory for the Fabric environment, built around native `fab` CLI commands.

For transferring and running this project on another machine, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Tool priority

1. Native `fab` commands.
2. `fab api` only when no native command can provide the required information.
3. Direct REST only when neither native `fab` nor `fab api` can perform the operation.

Both fallback levels are disabled in `config/inventory.config.json`. The current implementation uses native `fab` commands only.

Compatibility marker: `fab version 1.0.1 (07-2025)`. `Reusable.ps1` is the file to copy into another project when these helpers are needed.

## Individually testable blocks

- `scripts/01-Get-Capacities.ps1`: `fab ls .capacities -l` → `output/capacities.json`
- `scripts/02-Get-Workspaces.ps1`: `fab ls -l` → capacity-linked and unassigned workspaces
- `scripts/03-Get-WorkspaceItems.ps1`: native workspace `fab ls ... -l` → typed items
- `scripts/04-Get-SemanticModels.ps1`: native `fab get ... -q . -f` → sources, tables, fields, calculated objects, measures, measure references, and relationships with keys
- `scripts/05-Get-Reports.ps1`: native report definition → semantic-model connection and object references
- `scripts/06-Build-Lineage.ps1`: builds lineage only between distinct objects: data source → semantic model and semantic model → report

Run a block:

```powershell
pwsh -NoProfile -File .\scripts\01-Get-Capacities.ps1
```

Scope an item-list test without scanning every workspace:

```powershell
pwsh -NoProfile -File .\scripts\03-Get-WorkspaceItems.ps1 -WorkspaceName AdventureDS
```

Run the united flow from a Windows console:

```powershell
.\Invoke-FabricInventory.bat -Stage All
```

Run local parser tests:

```powershell
pwsh -NoProfile -File .\tests\Test-Reusable.ps1
```

## Coverage notes

- Inventory covers objects visible to the current `fab` identity; it does not claim tenant-admin completeness.
- Definition retrieval can fail for protected/service-managed models or insufficient permission. Failures are retained in JSON instead of silently skipped.
- Measure dependency edges are resolved from DAX references in exported TMDL. Ambiguous column/measure names remain a documented limitation; exact engine dependency metadata would require a separate XMLA block rather than REST.
- Credentials are never exported. Data-source connection identity and model source expressions are inventory metadata and can still be sensitive.

## Verified run — 2026-09-28

The complete native-CLI run produced 3 capacities, 114 workspaces, 459 items across 20 item types, 72 semantic models, and 40 reports. Definition extraction succeeded for 68 semantic models and 36 reports. Four service-managed models and their four reports denied definition export; their exact native CLI errors are retained in the JSON outputs. The normalized model output contains 263 tables, 2,852 fields, 187 measures, and 172 schema relationships. Table relationships and measure dependencies remain inside `semantic-models.json`; report field bindings remain inside `reports.json`. `lineage.json` contains 91 relationships between distinct objects: 55 data source → semantic model and 36 semantic model → report.
