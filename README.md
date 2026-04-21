
<!-- README.md is generated from README.Rmd. Please edit that file -->

# rschrodinger: A High-Performance Data Bridge between Schrödinger and R

<!-- badges: start -->

<!-- badges: end -->

**rschrodinger** is not an attempt to recreate the entire Schrödinger
suite or its Python API in R. Instead, it is a **small, fast, and
focused data bridge** designed specifically for AIDD (AI-driven Drug
Discovery) developers who need seamless data transit between
Schrödinger’s computational engines and R’s robust statistical and
bioinformatics ecosystems.

## Why this package exists (The 30% Time Sink)

In modern CADD pipelines, Schrödinger dominates computation (Docking,
MD, QM), but downstream biological statistics, visualization, and
modeling often happen in R or Python. Currently, R users are stranded:
they must rely on clunky shell scripts, intermediate `.sdf`/`.csv` file
conversions via `structconvert`, or wrestle with environment-destroying
Python reticulate configurations.

This package provides a pragmatic, architecture-level solution to bypass
three massive hurdles of wrapping Schrödinger: 1. **The Environment
Nightmare**: Calling `$SCHRODINGER/run` aggressively overrides system
dynamic libraries (`libstdc++`, etc.), causing silent segfaults when
linked alongside Rcpp or `data.table`. 2. **The License Blackbox
(SLM)**: Deeply wrapping C++ instances triggers Schrödinger License
Manager (SLM) checks. Navigating this via unapproved bridges is
technically fragile and legally risky (EULA violations). 3. **The `.mae`
Format Abyss**: Maestro files (`.mae`) are highly nested, and
regex-based R parsers inevitably drop critical data like Epik
protonation states or Glide score components.

## Architecture Philosophy

> *“Don’t rebuild the Schrödinger console in R. Build a pipeline.”*

We strictly avoided “thick wrappers” that attempt to inherit C++ memory
ownership or rewrite algorithm dispatchers. `rschrodinger` focuses on
three core pillars:

### 1. `read_mae_fast()`: The Native `.mae` Extractor

Bypasses the `structconvert -> SDF -> R` bottleneck entirely. Built on
**Rcpp + maeparser** (Schrödinger’s MIT-licensed C++ parser), it safely
extracts molecular structures, interaction topologies, and custom
properties (like `r_i_glide_gscore`) directly into an R
`tibble`/`data.table`. - **Zero License Risk** (pure open-source C++) -
**Zero Data Loss** (direct parsing, no intermediate formats)

### 2. `get_protein_ligand_interactions()`: The Sandboxed Interactor

A heavily isolated micro-bridge using `reticulate` to invoke
Schrödinger’s `schrodinger.structutils.interactions.pi`. It executes
completely inside an ephemeral, strictly sandboxed `$SCHRODINGER/run`
background process, returning a neat `data.frame` of distances, angles,
and Pi-stack contacts, then immediately destroying the context to
protect the R host environment.

### 3. `poll_job_status()`: The Asynchronous Job Poller

Ditch flaky file-timestamp checking. A clean REST-like R wrapper over
`schrodinger.job.jobcontrol` to check job IDs and return standardized
statuses (`ACTIVE`, `COMPLETED`, `DIED`) for resilient workflow
automation.

## Installation

You can install the development version of rschrodinger from GitHub:

``` r
# install.packages("remotes")
remotes::install_github("jixing475/rschrodinger")
```

## Example Usage

``` r
library(rschrodinger)

# 1. Ultra-fast native .mae reading into a tibble
hits_df <- read_mae_fast("docking_results.maegz", properties = c("r_i_glide_gscore", "s_m_title"))

# 2. Extract detailed protein-ligand interactions safely
interactions <- get_protein_ligand_interactions("complex.maegz")

# 3. Check HPC job status
status <- poll_job_status("localhost-0-61a8b9")
```
