test_that("poll_job_status errors without SCHRODINGER", {
    withr::local_envvar(SCHRODINGER = "")
    expect_error(
        poll_job_status("test_job_123"),
        "not set"
    )
})

test_that("poll_job_status errors on bad SCHRODINGER path", {
    withr::local_envvar(SCHRODINGER = "/nonexistent/schrodinger")
    expect_error(
        poll_job_status("test_job_123"),
        "not found"
    )
})

test_that("poll_job_status errors on empty job_id", {
    skip_if(
        !nzchar(Sys.getenv("SCHRODINGER")),
        "SCHRODINGER not set"
    )
    expect_error(
        poll_job_status(""),
        "non-empty"
    )
})

test_that("poll_job_status errors on non-character job_id", {
    skip_if(
        !nzchar(Sys.getenv("SCHRODINGER")),
        "SCHRODINGER not set"
    )
    expect_error(
        poll_job_status(42),
        "non-empty"
    )
})

test_that("job_status_python_script returns valid Python code", {
    script <- rschrodinger:::job_status_python_script()
    expect_type(script, "character")
    expect_true(grepl("import sys", script))
    expect_true(grepl("jobcontrol", script))
    expect_true(grepl("get_job_status", script))
})

test_that("normalize_job_status maps correctly", {
    norm <- rschrodinger:::normalize_job_status
    expect_equal(norm("completed"), "completed")
    expect_equal(norm("done"), "completed")
    expect_equal(norm("finished"), "completed")
    expect_equal(norm("running"), "running")
    expect_equal(norm("active"), "running")
    expect_equal(norm("launched"), "running")
    expect_equal(norm("submitted"), "running")
    expect_equal(norm("failed"), "failed")
    expect_equal(norm("died"), "failed")
    expect_equal(norm("killed"), "failed")
    expect_equal(norm("unknown"), "unknown")
    expect_equal(norm("something_weird"), "unknown")
})
