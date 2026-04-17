test_that("read_mae_fast parses example.mae correctly", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file)

    expect_s3_class(result, "tbl_df")
    expect_equal(nrow(result), 1L)
    expect_true("title" %in% names(result))
    expect_true("_ct_index" %in% names(result))
    expect_true("_source_file" %in% names(result))
    expect_equal(result[["_ct_index"]], 1L)
    expect_equal(result[["_source_file"]], "example.mae")
})

test_that("read_mae_fast strips prefixes by default", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file, strip_prefix = TRUE)
    expect_true("title" %in% names(result))
    expect_false("s_m_title" %in% names(result))
})

test_that("read_mae_fast preserves prefixes when strip_prefix = FALSE", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file, strip_prefix = FALSE)
    expect_true("s_m_title" %in% names(result))
    expect_false("title" %in% names(result))
})

test_that("read_mae_fast type-converts correctly", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file, strip_prefix = FALSE)

    r_cols <- grep("^r_", names(result), value = TRUE)
    if (length(r_cols) > 0) {
        expect_type(result[[r_cols[1]]], "double")
    }

    i_cols <- grep("^i_", names(result), value = TRUE)
    if (length(i_cols) > 0) {
        expect_type(result[[i_cols[1]]], "integer")
    }

    s_cols <- grep("^s_", names(result), value = TRUE)
    if (length(s_cols) > 0) expect_type(result[[s_cols[1]]], "character")
})

test_that("read_mae_fast filters properties", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file, properties = c("title", "ct_format"))
    expect_true("title" %in% names(result))
    expect_true("ct_format" %in% names(result))
    expect_false("PDB_CRYST1_a" %in% names(result))
})

test_that("read_mae_fast warns on missing requested properties", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    expect_warning(
        read_mae_fast(mae_file, properties = c("title", "nonexistent_prop")),
        "not found"
    )
})

test_that("read_mae_fast errors on missing file", {
    expect_error(read_mae_fast("/tmp/nonexistent_file.mae"), "does not exist")
})

test_that("read_mae_fast errors on non-character input", {
    expect_error(read_mae_fast(42), "must be a single character")
})

test_that("read_mae_fast errors on vector input", {
    expect_error(
        read_mae_fast(c("a.mae", "b.mae")),
        "must be a single character"
    )
})

test_that("read_mae_fast reads directory of .mae files", {
    tmp_dir <- withr::local_tempdir()
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    file.copy(mae_file, file.path(tmp_dir, "test1.mae"))
    file.copy(mae_file, file.path(tmp_dir, "test2.mae"))

    result <- read_mae_fast(tmp_dir)
    expect_s3_class(result, "tbl_df")
    expect_equal(nrow(result), 2L)
})

test_that("read_mae_fast errors on empty directory", {
    tmp_dir <- withr::local_tempdir()
    expect_error(read_mae_fast(tmp_dir), "No .mae or .maegz")
})

test_that("read_mae_fast with include_atoms = TRUE returns atoms", {
    mae_file <- system.file(
        "extdata",
        "example.mae",
        package = "rschrodinger",
        mustWork = TRUE
    )
    result <- read_mae_fast(mae_file, include_atoms = TRUE)
    expect_true("atoms" %in% names(result))
    expect_type(result$atoms, "list")
})

test_that("read_mae_fast handles .maegz files", {
    maegz <- file.path(
        "/tmp/task-agents/rschrodinger/context/testdata",
        "BRD4_Indomethacin_SP_pv.maegz"
    )
    skip_if_not(file.exists(maegz), "Test .maegz file not available")

    result <- read_mae_fast(maegz)
    expect_s3_class(result, "tbl_df")
    expect_gt(nrow(result), 1L)
    expect_true("glide_gscore" %in% names(result))
})

test_that("read_mae_fast .maegz glide_gscore matches ground truth", {
    maegz <- file.path(
        "/tmp/task-agents/rschrodinger/context/testdata",
        "BRD4_Indomethacin_SP_pv.maegz"
    )
    csv_file <- file.path(
        "/tmp/task-agents/rschrodinger/context/testdata",
        "BRD4_Indomethacin_SP.csv"
    )
    skip_if_not(
        file.exists(maegz) && file.exists(csv_file),
        "Test data not available"
    )

    result <- read_mae_fast(maegz)
    csv <- read.csv(csv_file)

    parsed_scores <- sort(round(
        result$glide_gscore[!is.na(result$glide_gscore)],
        3
    ))
    csv_scores <- sort(round(csv$r_i_glide_gscore, 3))
    expect_equal(parsed_scores, csv_scores)
})

test_that("parse_ct_block handles empty file gracefully", {
    tmp <- withr::local_tempfile(fileext = ".mae")
    writeLines(
        c(
            "{ ",
            " s_m_m2io_version",
            " :::",
            " 2.0.0 ",
            "} "
        ),
        tmp
    )

    result <- read_mae_fast(tmp)
    expect_equal(nrow(result), 0L)
})

test_that("bind_ct_rows handles CTs with different columns", {
    bind_fn <- rschrodinger:::bind_ct_rows
    ct_list <- list(
        list(a = 1, b = "x", `_ct_index` = 1L),
        list(a = 2, c = "y", `_ct_index` = 2L)
    )
    result <- bind_fn(ct_list)
    expect_equal(nrow(result), 2)
    expect_true(all(c("a", "b", "c") %in% names(result)))
    expect_true(is.na(result$b[2]))
    expect_true(is.na(result$c[1]))
})

test_that("read_mae_fast handles multi-CT .mae with property selection", {
    maegz <- file.path(
        "/tmp/task-agents/rschrodinger/context/testdata",
        "BRD4_Indomethacin_SP_pv.maegz"
    )
    skip_if_not(file.exists(maegz), "Test .maegz file not available")

    result <- read_mae_fast(maegz, properties = c("title", "glide_gscore"))
    expect_true("title" %in% names(result))
    expect_true("glide_gscore" %in% names(result))
    # Should have only selected properties + meta columns
    non_meta <- setdiff(
        names(result),
        c("_ct_index", "_source_file", "ct_index", "source_file")
    )
    expect_true(all(non_meta %in% c("title", "glide_gscore")))
})
