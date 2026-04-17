#' Extract Protein-Ligand Interactions
#'
#' Extract protein-ligand interactions from a complex structure using
#' Schrodinger's Python API in a sandboxed subprocess. Requires a
#' Schrodinger installation.
#'
#' @param complex_file Character. Path to the complex structure file
#'   (`.mae` or `.pdb`).
#' @param schrodinger_path Character. Path to Schrodinger installation
#'   directory. Defaults to the `SCHRODINGER` environment variable.
#'
#' @return A data.frame with columns: `interaction_type`, `residue`,
#'   `distance`, and additional details depending on interaction type.
#'
#' @examples
#' \dontrun{
#' interactions <- get_protein_ligand_interactions("complex.mae")
#' }
#'
#' @export
get_protein_ligand_interactions <- function(
    complex_file,
    schrodinger_path = Sys.getenv("SCHRODINGER")
) {
    # Validate inputs
    validate_schrodinger(schrodinger_path)

    if (!file.exists(complex_file)) {
        cli::cli_abort("Complex file does not exist: {.path {complex_file}}")
    }

    # Write Python script to tempfile
    py_script <- withr::local_tempfile(fileext = ".py")
    writeLines(interaction_python_script(), py_script)

    # Build command
    run_exe <- file.path(schrodinger_path, "run")
    complex_abs <- normalizePath(complex_file, mustWork = TRUE)

    # Execute in sandboxed subprocess
    result <- run_schrodinger_python(
        schrodinger_path = schrodinger_path,
        script_path = py_script,
        args = complex_abs
    )

    # Parse JSON output
    tryCatch(
        {
            parsed <- jsonlite::fromJSON(result$stdout)
            as.data.frame(parsed, stringsAsFactors = FALSE)
        },
        error = function(e) {
            cli::cli_abort(c(
                "Failed to parse interaction output.",
                "i" = "Python stderr: {result$stderr}",
                "x" = "Parse error: {conditionMessage(e)}"
            ))
        }
    )
}


#' Generate Python script for interaction extraction
#' @noRd
interaction_python_script <- function() {
    '
import sys, json

def extract_interactions(mae_path):
    """Extract protein-ligand interactions from a Schrodinger complex."""
    try:
        from schrodinger.structure import StructureReader
        from schrodinger.structutils.interactions import hbond
    except ImportError:
        print(json.dumps({"error": "schrodinger Python API not available"}))
        sys.exit(1)

    results = []
    try:
        reader = StructureReader(mae_path)
        st = next(reader)
        reader.close()

        # Separate protein and ligand atoms
        protein_atoms = [a.index for a in st.atom if a.chain.strip() != "" and a.pdbres.strip() not in ("", "UNK")]
        ligand_atoms = [a.index for a in st.atom if a.index not in protein_atoms]

        if not ligand_atoms:
            print(json.dumps([]))
            sys.exit(0)

        # Hydrogen bonds
        try:
            hbonds = hbond.get_hydrogen_bonds(st, atoms1=protein_atoms, atoms2=ligand_atoms)
            for hb in hbonds:
                a1, a2 = st.atom[hb[0]], st.atom[hb[1]]
                results.append({
                    "interaction_type": "hydrogen_bond",
                    "residue": f"{a1.pdbres.strip()}{a1.resnum}{a1.chain.strip()}",
                    "atom_protein": a1.pdbname.strip(),
                    "atom_ligand": a2.pdbname.strip(),
                    "distance": round(st.measure(hb[0], hb[1]), 2),
                    "angle": None
                })
        except Exception:
            pass

        # Close contacts (< 4.0 A)
        for pi in protein_atoms:
            for li in ligand_atoms:
                d = st.measure(pi, li)
                if d < 4.0 and d > 0.5:
                    pa = st.atom[pi]
                    la = st.atom[li]
                    results.append({
                        "interaction_type": "close_contact",
                        "residue": f"{pa.pdbres.strip()}{pa.resnum}{pa.chain.strip()}",
                        "atom_protein": pa.pdbname.strip(),
                        "atom_ligand": la.pdbname.strip(),
                        "distance": round(d, 2),
                        "angle": None
                    })

    except StopIteration:
        pass

    print(json.dumps(results))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: script.py <mae_path>"}))
        sys.exit(1)
    extract_interactions(sys.argv[1])
'
}
