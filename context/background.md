# rschrodinger — Background Context

## Source Article

Full audit: `/Users/zero/Desktop/zeroverse/Agent/alpha-os-zero/draft/articles/schrodinger-r-api-audit.md`

## Problem Statement

Schrödinger's computational chemistry tools (Glide, Desmond, etc.) output `.mae`
format files. R users must currently:
1. Convert `.mae` → SDF/PDB via `structconvert` (lossy)
2. Write throwaway Python scripts to extract properties → CSV → R (slow)
3. Manually poll HPC job status via file timestamps (fragile)

This package builds a **minimal data bridge** — not a full wrapper.

## Architecture Decisions

### Function 1: `read_mae_fast()`
- **Pure R parser** for `.mae` / `.maegz` files
- The `.mae` format is a text-based, nested, self-describing format
- Key challenge: `{` can be both block opener and string value
- Must extract property tables (atoms, bonds, metadata) into tibble/data.table
- Must handle `m2io` attribute prefix stripping (e.g., `r_i_glide_gscore` → `glide_gscore`)
- Must handle `.maegz` (gzipped `.mae`)
- **NO dependency on Schrödinger installation** — this is the whole point
- Reference: `maeparser` C++ library (MIT license) for parsing logic

### Function 2: `get_protein_ligand_interactions()`
- **Requires `$SCHRODINGER` installation** on the machine
- Uses `system()` to call `$SCHRODINGER/run python3 -c "..."` in a sandboxed subprocess
- The Python code calls `schrodinger.structutils.interactions.pi` etc.
- Returns an R data.frame with interaction types, distances, angles
- Key: environment isolation — NEVER pollute R session's env vars
- Must validate `$SCHRODINGER` path exists before attempting

### Function 3: `poll_job_status()`
- **Requires `$SCHRODINGER` installation**
- Uses `system()` to call `$SCHRODINGER/run python3 -c "..."` 
- Queries `schrodinger.job.jobcontrol` for job status
- Returns standardized status: "running", "completed", "failed", "unknown"
- Optional: `wait = TRUE` parameter to block until job completes (with timeout)

## Key Constraints

1. **Legal**: Only use MIT/Apache-licensed components. `maeparser` is MIT. Never
   reverse-engineer SLM or load proprietary `.so` libraries.
2. **Stability**: Schrödinger's Python API changes between versions. Keep the
   `system()` calls to minimal, version-agnostic Python snippets.
3. **Performance**: `read_mae_fast()` must handle files with 100k+ entries.
   Use vectorized R operations, pre-allocate memory.

## .mae Format Quick Reference

```
{                              ← file-level block
  s_m_title  "Compound_001"
  ...
  f_m_ct {                     ← CT (Connection Table) block
    s_m_title  "Compound_001"
    ...
    m_atom[N] {                ← indexed block (N atoms)
      # column names
      i_m_mmod_type
      r_m_x_coord
      r_m_y_coord
      r_m_z_coord
      ...
      :::                      ← separator between header and data
      1  2  1.234  5.678  9.012  ...
      2  1  3.456  7.890  1.234  ...
      ...
    }
    m_bond[M] { ... }
  }
}
```

Type prefixes: `s_` = string, `r_` = real, `i_` = integer, `b_` = boolean.
Namespace: `m_` = maestro, `user_` = user-defined, etc.

## Dependencies

- `tibble` or `data.table` for output
- `readr` for fast line reading (optional)
- `cli` for user-facing messages
- `withr` for environment isolation in sandboxed calls
- `processx` for subprocess management (preferred over raw system())
