#' Validate Schrodinger installation path
#'
#' @param schrodinger_path Path to check.
#' @noRd
validate_schrodinger <- function(schrodinger_path) {
    if (!nzchar(schrodinger_path)) {
        cli::cli_abort(c(
            "Schrodinger path not set.",
            "i" = "Set the {.envvar SCHRODINGER} environment variable,",
            "i" = "or pass {.arg schrodinger_path} explicitly."
        ))
    }

    if (!dir.exists(schrodinger_path)) {
        cli::cli_abort(
            "Schrodinger directory not found: {.path {schrodinger_path}}"
        )
    }

    run_exe <- file.path(schrodinger_path, "run")
    if (!file.exists(run_exe)) {
        cli::cli_abort(
            "Schrodinger {.file run} executable not found at {.path {run_exe}}"
        )
    }

    invisible(TRUE)
}


#' Run a Python script via Schrodinger's sandboxed interpreter
#'
#' Uses `processx::run()` for clean subprocess management.
#' Environment is strictly isolated — only `SCHRODINGER` and minimal
#' system vars are passed through.
#'
#' @param schrodinger_path Path to Schrodinger installation.
#' @param script_path Path to the Python script to execute.
#' @param args Additional command-line arguments (character vector).
#' @param timeout_sec Timeout in seconds (default 300).
#'
#' @return A list with `stdout` and `stderr` strings.
#' @noRd
run_schrodinger_python <- function(
    schrodinger_path,
    script_path,
    args = character(),
    timeout_sec = 300
) {
    run_exe <- file.path(schrodinger_path, "run")

    # Build minimal clean environment
    clean_env <- c(
        SCHRODINGER = schrodinger_path,
        PATH = Sys.getenv("PATH"),
        HOME = Sys.getenv("HOME"),
        TMPDIR = tempdir()
    )

    cmd_args <- c("python3", script_path, args)

    result <- tryCatch(
        processx::run(
            command = run_exe,
            args = cmd_args,
            env = clean_env,
            timeout = timeout_sec,
            error_on_status = FALSE
        ),
        error = function(e) {
            cli::cli_abort(c(
                "Failed to execute Schrodinger Python.",
                "x" = conditionMessage(e)
            ))
        }
    )

    if (result$status != 0 && !nzchar(result$stdout)) {
        cli::cli_abort(c(
            "Schrodinger Python script failed (exit code {result$status}).",
            "i" = "stderr: {result$stderr}"
        ))
    }

    result
}
