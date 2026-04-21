# Read Maestro (.mae/.maegz) Files

Parse Schrodinger Maestro format files natively in R without requiring a
Schrodinger installation. Extracts CT (Connection Table) level
properties into a tidy tibble.

## Usage

``` r
read_mae_fast(
  path,
  properties = NULL,
  strip_prefix = TRUE,
  include_atoms = FALSE
)
```

## Arguments

- path:

  Character. Path to a `.mae` or `.maegz` file, or a directory (reads
  all `.mae`/`.maegz` files in it).

- properties:

  Character vector or `NULL`. If specified, only extract these
  properties (matched after prefix stripping if `strip_prefix` is
  `TRUE`). `NULL` extracts all CT-level properties.

- strip_prefix:

  Logical. If `TRUE` (default), strip m2io type and namespace prefixes
  from property names (e.g., `r_i_glide_gscore` becomes `glide_gscore`).

- include_atoms:

  Logical. If `TRUE`, include atom data as a list-column named `atoms`.
  Default is `FALSE`.

## Value

A tibble where each row is one CT (Connection Table) entry. Columns are
the extracted properties, plus `_ct_index` (integer) and `_source_file`
(character) tracking provenance.

## Examples

``` r
mae_file <- system.file("extdata", "example.mae",
  package = "rschrodinger", mustWork = TRUE)
read_mae_fast(mae_file)
#> # A tibble: 1 × 19
#>   title PDB_CRYST1_a PDB_CRYST1_b PDB_CRYST1_c PDB_CRYST1_alpha PDB_CRYST1_beta
#>   <chr>        <dbl>        <dbl>        <dbl>            <dbl>           <dbl>
#> 1 3MXF          36.8         44.8         78.4               90              90
#> # ℹ 13 more variables: PDB_CRYST1_gamma <dbl>, PDB_CRYST1_z <int>,
#> #   source_file_index <int>, PDB_TITLE <chr>, PDB_ID <chr>,
#> #   PDB_CRYST1_Space_Group <chr>, PDB_CLASSIFICATION <chr>,
#> #   PDB_DEPOSITION_DATE <chr>, PDB_format_version <chr>, source_file <chr>,
#> #   ct_format <int>, `_ct_index` <int>, `_source_file` <chr>
```
