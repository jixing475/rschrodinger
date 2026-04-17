test_that("get_protein_ligand_interactions errors without SCHRODINGER", {
    withr::local_envvar(SCHRODINGER = "")
    expect_error(
        get_protein_ligand_interactions("fake_complex.mae"),
        "not set"
    )
})

test_that("get_protein_ligand_interactions errors on bad path", {
    withr::local_envvar(SCHRODINGER = "/nonexistent/schrodinger")
    expect_error(
        get_protein_ligand_interactions("fake_complex.mae"),
        "not found"
    )
})

test_that("get_protein_ligand_interactions errors on missing file", {
    skip_if(
        !nzchar(Sys.getenv("SCHRODINGER")),
        "SCHRODINGER not set"
    )
    expect_error(
        get_protein_ligand_interactions("/tmp/nonexistent_complex.mae"),
        "does not exist"
    )
})

test_that("interaction_python_script returns valid Python code", {
    script <- rschrodinger:::interaction_python_script()
    expect_type(script, "character")
    expect_true(grepl("import sys", script))
    expect_true(grepl("json.dumps", script))
    expect_true(grepl("extract_interactions", script))
})
