test_that("validate_schrodinger errors on empty path", {
    validate <- rschrodinger:::validate_schrodinger
    expect_error(validate(""), "not set")
})

test_that("validate_schrodinger errors on nonexistent directory", {
    validate <- rschrodinger:::validate_schrodinger
    expect_error(validate("/nonexistent/path"), "not found")
})

test_that("validate_schrodinger errors when run executable missing", {
    validate <- rschrodinger:::validate_schrodinger
    tmp_dir <- withr::local_tempdir()
    expect_error(validate(tmp_dir), "run.*not found")
})

test_that("validate_schrodinger passes with valid path", {
    validate <- rschrodinger:::validate_schrodinger
    tmp_dir <- withr::local_tempdir()
    # Create a fake 'run' executable
    run_path <- file.path(tmp_dir, "run")
    writeLines("#!/bin/bash", run_path)
    Sys.chmod(run_path, "755")
    expect_invisible(validate(tmp_dir))
})

test_that("strip_mae_prefix strips type_namespace prefix", {
    strip <- rschrodinger:::strip_mae_prefix
    expect_equal(strip("r_i_glide_gscore"), "glide_gscore")
    expect_equal(strip("s_m_title"), "title")
    expect_equal(strip("i_m_ct_format"), "ct_format")
    expect_equal(strip("r_pdb_PDB_CRYST1_a"), "PDB_CRYST1_a")
    expect_equal(strip("b_m_some_flag"), "some_flag")
})

test_that("strip_mae_prefix preserves meta columns", {
    strip <- rschrodinger:::strip_mae_prefix
    expect_equal(strip("_ct_index"), "_ct_index")
    expect_equal(strip("_source_file"), "_source_file")
})

test_that("strip_mae_prefix handles edge cases", {
    strip <- rschrodinger:::strip_mae_prefix
    expect_equal(strip("plain_name"), "plain_name")
    expect_equal(strip("x"), "x")
    expect_equal(strip(""), "")
})

test_that("parse_mae_value handles types", {
    parse <- rschrodinger:::parse_mae_value
    expect_equal(parse("\"hello world\""), "hello world")
    expect_true(is.na(parse("<>")))
    expect_equal(parse("42"), "42")
    expect_equal(parse("3.14"), "3.14")
    expect_equal(parse("plain"), "plain")
})

test_that("type_convert_mae converts by prefix", {
    convert <- rschrodinger:::type_convert_mae
    result <- convert(list(
        r_value = "3.14",
        i_count = "42",
        s_name = "hello",
        b_flag = "1"
    ))
    expect_type(result$r_value, "double")
    expect_equal(result$r_value, 3.14)
    expect_type(result$i_count, "integer")
    expect_equal(result$i_count, 42L)
    expect_type(result$s_name, "character")
    expect_equal(result$s_name, "hello")
    expect_type(result$b_flag, "logical")
    expect_true(result$b_flag)
})

test_that("type_convert_mae handles FALSE boolean", {
    convert <- rschrodinger:::type_convert_mae
    result <- convert(list(b_flag = "0"))
    expect_false(result$b_flag)
})

test_that("type_convert_mae handles NA", {
    convert <- rschrodinger:::type_convert_mae
    result <- convert(list(r_value = NA_character_))
    expect_true(is.na(result$r_value))
})

test_that("split_mae_data_line handles quoted strings", {
    split_fn <- rschrodinger:::split_mae_data_line
    result <- split_fn('  1 35 35.982 2.596 "SER " " N  " 7')
    expect_equal(result[1], "1")
    expect_equal(result[2], "35")
    expect_equal(result[5], "SER ")
    expect_equal(result[6], " N  ")
    expect_equal(result[7], "7")
})

test_that("split_mae_data_line handles empty markers", {
    split_fn <- rschrodinger:::split_mae_data_line
    result <- split_fn("  1 <> 3.14 <>")
    expect_equal(result[1], "1")
    expect_equal(result[2], "<>")
    expect_equal(result[3], "3.14")
    expect_equal(result[4], "<>")
})

test_that("split_mae_data_line handles empty string", {
    split_fn <- rschrodinger:::split_mae_data_line
    result <- split_fn("")
    expect_length(result, 0)
})

test_that("split_mae_data_line handles tabs", {
    split_fn <- rschrodinger:::split_mae_data_line
    result <- split_fn("1\t2\t3")
    expect_equal(result, c("1", "2", "3"))
})

test_that("run_schrodinger_python errors gracefully on bad path", {
    run_fn <- rschrodinger:::run_schrodinger_python
    expect_error(
        run_fn("/nonexistent/path", "/tmp/fake_script.py"),
        class = "rlang_error"
    )
})
