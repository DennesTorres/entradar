# Email template — execution instructions

**Subject:** Fabric Inventory — setup and execution

Hi <NAME>,

The Fabric Inventory project is available at `<PROJECT_LOCATION>` in source control.

After obtaining the project, please start with the documentation included in its root folder:

- `README.md` — purpose, structure, processing stages, scope, limitations, and verified results.
- `DEPLOYMENT.md` — authoritative prerequisites, Fabric CLI installation, authentication, smoke tests, execution commands, outputs, and security notes.

Supporting references are also included:

- `config/inventory.config.json` — runtime configuration and native-`fab` tool priority.
- `Reusable.ps1` — shared functions and Fabric CLI compatibility marker.
- `tests/Test-All.ps1` — complete reusable-function, governance-metadata, and lineage-separation validation suite.

The minimum runtime requirements are Windows PowerShell 5.1, Python 3.10–3.13, and `ms-fabric-cli` 1.7.0. The exact prerequisite and installation commands are under **Target-machine prerequisites** and **Install the pinned Fabric CLI** in `DEPLOYMENT.md`.

Authentication must be completed on the execution machine using the identity whose accessible Fabric environment should be inventoried:

```bat
fab auth login
```

Before the full run, complete the checks under **Smoke test** in `DEPLOYMENT.md`.

Run the complete inventory from `cmd.exe` in the project root:

```bat
Invoke-FabricInventory.bat -Stage All
```

The processing stages and individually runnable scripts are documented under **Individually testable blocks** in `README.md` and **Run or repeat one block** in `DEPLOYMENT.md`.

The generated files are written under `output`:

- `capacities.json`
- `workspaces.json`
- `items.json`
- `semantic-models.json`
- `reports.json`
- `lineage.json`

Please review the `errors` arrays in the generated JSON. A successful process exit does not mean every protected or service-managed definition was exportable. See **Coverage notes** in `README.md` and **Security and coverage** in `DEPLOYMENT.md`.

The generated `output/*.json` files are intentionally excluded by `.gitignore`. They can contain connection identities, source expressions, object names, model metadata, and lineage information, so they should be reviewed before being shared or explicitly added to source control.

Regards,

<SENDER_NAME>
