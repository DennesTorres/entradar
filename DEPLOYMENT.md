# Deployment instructions

## What to transfer

Transfer the complete clean project package: `Inventory-deployment-fabcli-1.0.1.zip`.

The deployment ZIP contains the scripts, configuration, tests, reusable functions, launcher, and an empty `output` folder. It deliberately excludes the JSON inventory generated on the source machine. Fabric authentication files and credentials are not part of the package.

## Target-machine prerequisites

- Windows with `cmd.exe`.
- Windows PowerShell 5.1 (`powershell.exe`) or later. PowerShell 7 is not required.
- Python 3.10, 3.11, 3.12, or 3.13 available through `python`.
- Network access to Microsoft Fabric sign-in and service endpoints.
- A Fabric identity with access to the capacities, workspaces, items, semantic models, and reports that must be inventoried.

## Install the pinned Fabric CLI

Open `cmd.exe` and run:

```bat
powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion"
python --version
python -m pip install ms-fabric-cli==1.0.1
fab --version
```

The PowerShell version must be 5.1 or later.

The expected CLI response is:

```text
fab version 1.0.1 (07-2025)
```

The project checks and records this compatibility version in `Reusable.ps1`. Do not silently upgrade the CLI for a production run; validate a newer version separately first.

## Copy and unpack

1. Copy `Inventory-deployment-fabcli-1.0.1.zip` to the target machine.
2. Create a normal writable folder, for example `C:\FabricTools\Inventory`.
3. Extract the ZIP contents into that folder.
4. Confirm that `Invoke-FabricInventory.bat`, `Invoke-FabricInventory.ps1`, `Reusable.ps1`, `scripts`, `config`, `tests`, and `output` are present directly inside that folder.

Do not place the project under a protected system folder such as `C:\Program Files`, because the process writes JSON files under `output`.

## Authenticate on the target machine

From `cmd.exe`, change to the extracted folder and sign in:

```bat
cd /d C:\FabricTools\Inventory
fab auth login
```

For a user-run inventory, select **Interactive with a web browser** and authenticate with the account whose accessible Fabric environment should be inventoried.

Do not copy the source machine's Fabric CLI authentication cache. Authentication belongs to the target machine and target identity.

## Smoke test

Run these native CLI checks before the inventory:

```bat
fab --version
fab ls .capacities -l
fab ls -l
powershell.exe -NoProfile -File tests\Test-Reusable.ps1
```

Expected results:

- The CLI version is `1.0.1 (07-2025)`.
- Capacity and workspace tables are returned.
- The reusable test ends with `Reusable tests passed.`

If `fab ls` returns fewer workspaces than expected, verify the signed-in identity and its workspace roles before running the full inventory.

## Run the complete inventory

From `cmd.exe` in the project folder:

```bat
Invoke-FabricInventory.bat -Stage All
```

The launcher uses Windows PowerShell 5.1 and executes the blocks in this order:

1. capacities;
2. workspaces and capacity assignments;
3. typed workspace items;
4. semantic-model metadata;
5. report metadata;
6. object-to-object lineage. Internal table relationships, measure dependencies, and report field bindings stay in their respective semantic-model or report JSON files.

The complete run can take several minutes because native `fab` commands are executed for every accessible workspace, semantic model, and report.

## Output files

The target machine writes these files under `output`:

- `capacities.json`
- `workspaces.json`
- `items.json`
- `semantic-models.json`
- `reports.json`
- `lineage.json`

Errors for inaccessible workspaces or definitions are retained inside the corresponding JSON file. A successful process exit does not mean every protected definition was exportable; inspect the `errors` arrays.

## Run or repeat one block

Each block can be tested independently:

```bat
powershell.exe -NoProfile -File scripts\01-Get-Capacities.ps1
powershell.exe -NoProfile -File scripts\02-Get-Workspaces.ps1
powershell.exe -NoProfile -File scripts\03-Get-WorkspaceItems.ps1
powershell.exe -NoProfile -File scripts\04-Get-SemanticModels.ps1
powershell.exe -NoProfile -File scripts\05-Get-Reports.ps1
powershell.exe -NoProfile -File scripts\06-Build-Lineage.ps1
```

Later blocks depend on the JSON produced by earlier blocks.

## Security and coverage

- The package contains no credentials.
- The output may contain connection identities, source expressions, object names, and report metadata; protect it as environment metadata.
- The inventory represents objects visible to the authenticated identity. It does not imply tenant-admin completeness.
- The implementation uses native `fab` commands. It contains no active `fab api` or direct REST invocation.
