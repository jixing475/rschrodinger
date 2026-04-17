# rschrodinger — Autonomous Build

You are building an R package autonomously. The human is not here.
Do NOT ask questions. If something is unclear, make your best judgment.

## Setup

1. Read this file completely.
2. Read `CLAUDE.md` — the full package specification.
3. Read `context/background.md` — technical context and .mae format reference.
4. Read `context/mae-format-spec.mae` — example .mae file (USE THIS as test fixture).
5. Read `evaluate.R` — understand how you're scored. **Do not modify it.**
6. Read `.claude/skills/r-package-builder/SKILL.md` — the build protocol.
7. Read `.claude/skills/r-coding-patterns/SKILL.md` — R coding conventions.
8. Create `progress.tsv` with header if it doesn't exist:
   `echo "phase\tattempt\tstatus\tscore\tdescription\tcommit" > progress.tsv`
9. Create the package scaffold with `usethis::create_package(".", open = FALSE)`
10. Copy `context/mae-format-spec.mae` → `inst/extdata/example.mae`
11. Verify baseline: `Rscript evaluate.R 1 > eval.log 2>&1`
12. Confirm Phase 1 passes, then start building.

## What To Build

**Package**: rschrodinger
**Purpose**: Fast data bridge between Schrödinger computational chemistry tools and R

**Functions to implement** (see CLAUDE.md for detailed specs):
1. `read_mae_fast(path, properties, strip_prefix)` — Pure R .mae parser → tibble
2. `get_protein_ligand_interactions(complex_file, schrodinger_path)` — Sandboxed Python subprocess → data.frame
3. `poll_job_status(job_id, schrodinger_path, wait, timeout, interval)` — Job status query → list

**Dependencies**: tibble, cli, processx, jsonlite, withr, rlang

## The Loop

```
current_phase = 1

LOOP:
  1. Decide what to do next based on:
     - Current phase requirements (see Phase Table below)
     - Previous failures in progress.tsv
     - Error messages from eval.log

  2. Make changes to R/, tests/, DESCRIPTION, NEWS.md, or README
     - Follow coding conventions (|> not %>%, \() lambdas, .data$ pronoun)
     - Keep changes focused — one logical unit per commit

  3. git add -A && git commit -m "phase-N: description"

  4. Rscript evaluate.R <current_phase> > eval.log 2>&1

  5. Read results: grep "^status:\|^score:\|^errors:" eval.log

  6. Record in progress.tsv:
     COMMIT=$(git rev-parse --short HEAD)
     # Append: phase, attempt, status, score, description, commit

  7. If status == PASS:
     - current_phase += 1
     - If current_phase > 6: print final report and EXIT
     - Reset attempt counter to 0

  8. If status == FAIL:
     - attempt += 1
     - If attempt > 10: print diagnostics and EXIT
     - Read errors, plan a DIFFERENT fix
     - Go to step 1

NEVER STOP to ask the human. They are asleep.
If you run out of ideas, re-read the source material,
re-read the error messages, try a fundamentally different approach.
```

## Phase Table

| Phase | Goal | What To Do | Pass Condition |
|-------|------|-----------|----------------|
| 1 | Scaffold | `usethis::create_package()` basics | `load_all()` works |
| 2 | Functions | Write all 3 functions in `R/`, add `@export` | All 3 required functions exported and callable |
| 3 | Docs | Add `@param`, `@return`, `@examples` to all exports | `devtools::document()` + all exports documented |
| 4 | Tests | Write `tests/testthat/test-*.R` | `devtools::test()` — 0 failures, coverage ≥ 80% |
| 5 | Check | Fix any errors/warnings | `devtools::check()` — 0 errors, 0 warnings |
| 6 | Polish | README content, NEWS.md, example .mae file | README + NEWS.md + examples + inst/extdata/example.mae |

## Coding Conventions

- Use `|>` not `%>%`
- Use `\() ...` for single-line lambdas
- Every exported function: `@export`, `@param`, `@return`, `@examples`
- Internal functions: `@noRd` or no roxygen
- Tests: `R/foo.R` → `tests/testthat/test-foo.R`
- Use `withr` in tests for temporary state
- Wrap roxygen at 80 chars
- After ANY roxygen change: run `Rscript -e "devtools::document()"`
- Namespace all external functions: `tibble::tibble()`, `cli::cli_abort()`, etc.
- Use `.data$col` for dplyr NSE inside package code

## What You CAN Do

- Create/modify files in `R/`
- Create/modify files in `tests/testthat/`
- Edit `DESCRIPTION` (add deps, update metadata)
- Edit `README.Rmd`, `README.md`, `NEWS.md`
- Create files in `inst/extdata/`
- Run R commands via `Rscript -e "..."`

## What You CANNOT Do

- Modify `evaluate.R` — it is read-only
- Modify `program.md` — it is human-owned
- Install system-level dependencies
- Ask the human anything
- Stop the loop before Phase 6 passes or 10 fails

## Strategy

**Build order**: `read_mae_fast()` first (highest value, zero external deps),
then `poll_job_status()` (simpler subprocess pattern), then
`get_protein_ligand_interactions()` (most complex subprocess).

**For the .mae parser**:
- Focus on CT-level property extraction (the flat properties like `r_i_glide_gscore`)
- Use `readLines()` + state machine approach (track whether inside a block)
- Handle `.maegz` via `gzfile()` connection
- Atom/bond blocks: extract into list-columns or nested tibbles
- Test with `inst/extdata/example.mae`

**For subprocess functions**:
- Use `processx::run()` for clean subprocess management
- Write minimal Python snippets as temp files
- Parse JSON output from Python
- Skip tests when `$SCHRODINGER` is not available: `testthat::skip_if_not()`
- But DO test error handling (bad paths, missing env, etc.)

**Performance**: Pre-allocate vectors, avoid growing lists in loops.
For large files, consider reading all lines first then processing.
