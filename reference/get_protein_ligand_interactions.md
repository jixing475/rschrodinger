# Extract Protein-Ligand Interactions

Extract protein-ligand interactions from a complex structure using
Schrodinger's Python API in a sandboxed subprocess. Requires a
Schrodinger installation.

## Usage

``` r
get_protein_ligand_interactions(
  complex_file,
  schrodinger_path = Sys.getenv("SCHRODINGER")
)
```

## Arguments

- complex_file:

  Character. Path to the complex structure file (`.mae` or `.pdb`).

- schrodinger_path:

  Character. Path to Schrodinger installation directory. Defaults to the
  `SCHRODINGER` environment variable.

## Value

A data.frame with columns: `interaction_type`, `residue`, `distance`,
and additional details depending on interaction type.

## Examples

``` r
if (FALSE) { # \dontrun{
interactions <- get_protein_ligand_interactions("complex.mae")
} # }
```
