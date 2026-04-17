#' Poll Schrodinger Job Status
#'
#' Query Schrodinger job status for HPC workflow integration.
#' Optionally block until the job completes or times out.
#'
#' @param job_id Character. The Schrodinger job ID.
#' @param schrodinger_path Character. Path to Schrodinger installation.
#'   Defaults to the `SCHRODINGER` environment variable.
#' @param wait Logical. If `TRUE`, block until job completes or timeout.
#'   Default is `FALSE`.
#' @param timeout Numeric. Max seconds to wait. Default is 3600 (1 hour).
#' @param interval Numeric. Seconds between polls when waiting. Default 30.
#'
#' @return A list with components:
#'   \describe{
#'     \item{status}{Character: "running", "completed", "failed", or "unknown".}
#'     \item{job_id}{The queried job ID.}
#'     \item{details}{Raw details from jobcontrol (list).}
#'   }
#'
#' @examples
#' \dontrun{
#' poll_job_status("my_job_12345")
#' poll_job_status("my_job_12345", wait = TRUE, timeout = 600)
#' }
#'
#' @export
poll_job_status <- function(
    job_id,
    schrodinger_path = Sys.getenv("SCHRODINGER"),
    wait = FALSE,
    timeout = 3600,
    interval = 30
) {
    # Validate
    validate_schrodinger(schrodinger_path)

    if (!is.character(job_id) || length(job_id) != 1 || !nzchar(job_id)) {
        cli::cli_abort("{.arg job_id} must be a non-empty string.")
    }

    if (wait) {
        poll_with_wait(job_id, schrodinger_path, timeout, interval)
    } else {
        query_job_once(job_id, schrodinger_path)
    }
}


#' Query job status once
#' @noRd
query_job_once <- function(job_id, schrodinger_path) {
    py_script <- withr::local_tempfile(fileext = ".py")
    writeLines(job_status_python_script(), py_script)

    result <- run_schrodinger_python(
        schrodinger_path = schrodinger_path,
        script_path = py_script,
        args = job_id
    )

    tryCatch(
        {
            parsed <- jsonlite::fromJSON(result$stdout)
            list(
                status = normalize_job_status(parsed$status %||% "unknown"),
                job_id = job_id,
                details = parsed
            )
        },
        error = function(e) {
            list(
                status = "unknown",
                job_id = job_id,
                details = list(
                    error = conditionMessage(e),
                    stderr = result$stderr
                )
            )
        }
    )
}


#' Poll with wait, blocking until complete or timeout
#' @noRd
poll_with_wait <- function(job_id, schrodinger_path, timeout, interval) {
    start_time <- Sys.time()
    elapsed <- 0

    cli::cli_inform("Waiting for job {.val {job_id}} (timeout: {timeout}s)...")

    repeat {
        result <- query_job_once(job_id, schrodinger_path)

        if (result$status %in% c("completed", "failed")) {
            cli::cli_inform(
                "Job {.val {job_id}} finished with status: {.val {result$status}}"
            )
            return(result)
        }

        elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
        if (elapsed >= timeout) {
            cli::cli_warn(
                "Timeout ({timeout}s) reached. Job still {.val {result$status}}."
            )
            return(result)
        }

        remaining <- timeout - elapsed
        wait_time <- min(interval, remaining)
        cli::cli_inform(
            "Job {.val {result$status}}, elapsed {round(elapsed)}s. Next poll in {wait_time}s..."
        )
        Sys.sleep(wait_time)
    }
}


#' Normalize Schrodinger job status to standard strings
#' @noRd
normalize_job_status <- function(status) {
    status_lower <- tolower(status)
    if (status_lower %in% c("completed", "done", "finished")) {
        return("completed")
    }
    if (status_lower %in% c("running", "active", "launched", "submitted")) {
        return("running")
    }
    if (status_lower %in% c("failed", "died", "killed", "error")) {
        return("failed")
    }
    "unknown"
}


#' Generate Python script for job status query
#' @noRd
job_status_python_script <- function() {
    '
import sys, json

def get_job_status(job_id):
    """Query Schrodinger job status."""
    try:
        from schrodinger.job import jobcontrol
    except ImportError:
        print(json.dumps({"status": "unknown", "error": "jobcontrol not available"}))
        sys.exit(0)

    try:
        job = jobcontrol.Job.getJob(job_id)
        if job is None:
            print(json.dumps({"status": "unknown", "error": f"Job {job_id} not found"}))
            sys.exit(0)

        info = {
            "status": str(job.Status),
            "job_id": job_id,
            "name": getattr(job, "Name", None),
            "program": getattr(job, "Program", None),
            "launch_time": str(getattr(job, "LaunchTime", "")),
            "duration": getattr(job, "Duration", None),
        }
        print(json.dumps(info))

    except Exception as e:
        print(json.dumps({"status": "unknown", "error": str(e)}))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"status": "unknown", "error": "Usage: script.py <job_id>"}))
        sys.exit(1)
    get_job_status(sys.argv[1])
'
}
