# rschrodinger 0.1.0

* Initial release.
* `read_mae_fast()`: Native R parser for Maestro `.mae` and `.maegz` files.
  - State-machine parser, zero Schrödinger dependency.
  - Automatic type conversion based on property name prefixes.
  - Prefix stripping for clean column names.
  - Directory scanning for batch processing.
  - Atom data extraction via `include_atoms` parameter.
* `get_protein_ligand_interactions()`: Extract protein-ligand interactions
  via sandboxed Schrödinger Python subprocess.
* `poll_job_status()`: Monitor Schrödinger HPC job status with optional
  blocking wait and configurable timeout.
