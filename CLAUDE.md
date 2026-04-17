# Task: Build rschrodinger R Package v0.1.0

## Goal

Build a minimal, high-performance R package that bridges Schrödinger computational
chemistry output data into R. Three functions, zero bloat.

## Context

Read `context/background.md` for full technical context and architecture decisions.
Read `context/mae-format-spec.mae` for the .mae file format example.

The audit article is at:
`/Users/zero/Desktop/zeroverse/Agent/alpha-os-zero/draft/articles/schrodinger-r-api-audit.md`

## Package Spec

- **Name**: `rschrodinger`
- **Title**: `Fast Data Bridge Between Schrodinger and R`
- **Description**: Read Maestro (.mae/.maegz) files natively in R without
  requiring a Schrödinger installation. Optionally bridge to Schrödinger's
  Python API for protein-ligand interaction analysis and job monitoring
  via sandboxed subprocess calls.
- **Author**: `person("Jixing", "Liu", email = "jixing.liu@example.com", role = c("aut", "cre", "cph"))`
- **License**: MIT
- **R**: >= 4.1.0

## Functions to Implement

### 1. `read_mae_fast(path, properties = NULL, strip_prefix = TRUE)`

**Purpose**: Parse .mae/.maegz files natively in R. No Schrödinger installation needed.

**Input**:
- `path`: Character. Path to a `.mae` or `.maegz` file, or a directory (reads all .mae/.maegz in it)
- `properties`: Character vector or NULL. If specified, only extract these properties. NULL = all.
- `strip_prefix`: Logical. If TRUE, strip `m2io` type/namespace prefixes (e.g., `r_i_glide_gscore` → `glide_gscore`)

**Output**: A tibble where each row is one CT (Connection Table) entry. Columns are the extracted properties. A `_ct_index` column tracks which CT block the row came from.

**Implementation Notes**:
- Parse the text-based .mae format using R's string processing
- Handle `.maegz` by decompressing via `gzfile()`
- The format uses `:::` as separator between header and data within indexed blocks
- Type prefixes: `s_` = string, `r_` = real, `i_` = integer, `b_` = boolean
- For CT-level properties (not atom/bond blocks), extract into a flat row
- For atom blocks (`m_atom[N]`), optionally return nested or as a list-column
- Pre-allocate and vectorize for performance on large files (100k+ CTs)

### 2. `get_protein_ligand_interactions(complex_file, schrodinger_path = Sys.getenv("SCHRODINGER"))`

**Purpose**: Extract protein-ligand interactions from a complex structure using Schrödinger's Python API in a sandboxed subprocess.

**Input**:
- `complex_file`: Character. Path to the complex structure file (.mae or .pdb)
- `schrodinger_path`: Character. Path to Schrödinger installation directory.

**Output**: A data.frame with columns: `interaction_type`, `residue`, `atom_ligand`, `atom_protein`, `distance`, `angle` (where applicable).

**Implementation Notes**:
- Validate `schrodinger_path` exists and contains `run` executable
- Write a minimal Python script to tempfile
- Execute via `processx::run()` with clean environment (only pass through necessary vars)
- Parse JSON output from the Python script
- Clean up temp files after execution
- NEVER modify R session environment variables

### 3. `poll_job_status(job_id, schrodinger_path = Sys.getenv("SCHRODINGER"), wait = FALSE, timeout = 3600, interval = 30)`

**Purpose**: Query Schrödinger job status for HPC workflow integration.

**Input**:
- `job_id`: Character. The Schrödinger job ID.
- `schrodinger_path`: Character. Path to Schrödinger installation.
- `wait`: Logical. If TRUE, block until job completes or timeout.
- `timeout`: Numeric. Max seconds to wait (default 3600 = 1 hour).
- `interval`: Numeric. Seconds between polls when waiting (default 30).

**Output**: A list with `status` ("running", "completed", "failed", "unknown"),
`job_id`, `start_time`, `elapsed`, and raw `details` from jobcontrol.

**Implementation Notes**:
- Same sandboxed execution pattern as `get_protein_ligand_interactions()`
- When `wait = TRUE`, loop with `Sys.sleep(interval)` and user-friendly `cli` progress
- Return standardized status strings regardless of Schrödinger version

## Dependencies

| Package | Type | Purpose |
|---------|------|---------|
| tibble | Imports | Output format for read_mae_fast |
| cli | Imports | User-facing messages and progress bars |
| processx | Imports | Sandboxed subprocess execution |
| jsonlite | Imports | Parse Python script output |
| withr | Imports | Environment isolation |
| rlang | Imports | .data pronoun, abort/warn/inform |
| testthat (>= 3.0.0) | Suggests | Testing |

## Constraints

- ❌ NEVER load Schrödinger's proprietary `.so` libraries
- ❌ NEVER use `library()` inside package code
- ❌ NEVER use `%>%` — use `|>`
- ❌ NEVER modify `evaluate.R` or this file
- ⚠️ `read_mae_fast()` must work WITHOUT Schrödinger installed
- ⚠️ `get_protein_ligand_interactions()` and `poll_job_status()` require `$SCHRODINGER`
  but must degrade gracefully with informative error if not available
- ⚠️ All `system()` / `processx::run()` calls must use clean environments
- ⚠️ Use `.data$col` pronoun for all dplyr NSE in package code
- ⚠️ inst/extdata/ should contain the example .mae file for tests

## Test Data

Real Schrödinger output files are in `context/testdata/`:
- `3MXF_A_clean.mae` (180KB) — PrepWizard output, 1 CT block, 1090 atoms, protein structure (BRD4)
- `BRD4_Indomethacin_SP_pv.maegz` (138KB) — Glide SP docking results, gzipped, multiple CT blocks with `r_i_glide_gscore` etc.
- `BRD4_Indomethacin_SP.csv` — Glide output CSV for ground truth validation (columns: `r_i_glide_gscore`, `r_i_glide_emodel`, etc.)

**For `inst/extdata/`**: The 3MXF file is too large for a package fixture. Create a minimal test .mae file
by extracting just the header + first 5 atoms from the real file. OR use the real file during development
and create a small synthetic fixture for the final package.

**Ground truth check**: After parsing `BRD4_Indomethacin_SP_pv.maegz`, the `r_i_glide_gscore` values
should match those in the CSV: -4.657, -4.949, -3.917, -2.811 (first 4 poses).

For functions 2 and 3, use `testthat::skip_if_not()` to skip when $SCHRODINGER is unavailable.

## Build Method

This package uses the **r-package-builder** autonomous pipeline.

1. Read `.claude/skills/r-package-builder/SKILL.md` for the full protocol
2. Read `.claude/skills/r-coding-patterns/SKILL.md` for R coding conventions
3. Follow the 6-phase pipeline with `evaluate.R` as the gate
4. Log progress to `progress.tsv`

## Strategy

**Priority order**: get `read_mae_fast()` rock-solid first — it's the highest
value function and has zero external dependencies. Then build the two
`$SCHRODINGER`-dependent functions. The parser is the hard part; the subprocess
wrappers are straightforward plumbing.

For the .mae parser, focus on **CT-level property extraction** first (the flat
properties like `r_i_glide_gscore`). Atom/bond block parsing is a Phase 2
nice-to-have — store raw lines in a list-column if you want, but the primary
value is getting those CT properties into a tibble at high speed.

For tests: the example .mae file in `inst/extdata/` gives you deterministic
test data. Functions 2 and 3 should have tests that skip when `$SCHRODINGER`
is not installed, plus tests that verify error handling for bad inputs.
