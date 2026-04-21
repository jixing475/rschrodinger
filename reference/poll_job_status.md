# Poll Schrodinger Job Status

Query Schrodinger job status for HPC workflow integration. Optionally
block until the job completes or times out.

## Usage

``` r
poll_job_status(
  job_id,
  schrodinger_path = Sys.getenv("SCHRODINGER"),
  wait = FALSE,
  timeout = 3600,
  interval = 30
)
```

## Arguments

- job_id:

  Character. The Schrodinger job ID.

- schrodinger_path:

  Character. Path to Schrodinger installation. Defaults to the
  `SCHRODINGER` environment variable.

- wait:

  Logical. If `TRUE`, block until job completes or timeout. Default is
  `FALSE`.

- timeout:

  Numeric. Max seconds to wait. Default is 3600 (1 hour).

- interval:

  Numeric. Seconds between polls when waiting. Default 30.

## Value

A list with components:

- status:

  Character: "running", "completed", "failed", or "unknown".

- job_id:

  The queried job ID.

- details:

  Raw details from jobcontrol (list).

## Examples

``` r
if (FALSE) { # \dontrun{
poll_job_status("my_job_12345")
poll_job_status("my_job_12345", wait = TRUE, timeout = 600)
} # }
```
