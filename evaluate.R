#!/usr/bin/env Rscript
# evaluate.R — Phase Gate Evaluation (LOCKED — do not modify)
#
# Usage: Rscript evaluate.R <phase>
# Phases: 1 (scaffold), 2 (functions), 3 (docs), 4 (tests), 5 (check), 6 (polish)
#
# Output format:
# ---
# phase:    <N>
# status:   PASS | FAIL
# score:    <details>
# errors:   <error messages if any>
# ---

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage: Rscript evaluate.R <phase_number>\n")
  quit(status = 1)
}

phase <- as.integer(args[1])
pkg_dir <- getwd()

# Helper: print structured output
report <- function(phase, status, score, errors = "") {
  cat("---\n")
  cat(sprintf("phase:    %d\n", phase))
  cat(sprintf("status:   %s\n", status))
  cat(sprintf("score:    %s\n", score))
  if (nzchar(errors)) {
    cat(sprintf("errors:   %s\n", gsub("\n", " | ", errors)))
  }
  cat("---\n")
}

# Required exports for this package
REQUIRED_EXPORTS <- c(
  "read_mae_fast",
  "get_protein_ligand_interactions",
  "poll_job_status"
)

# ── Phase 1: Scaffold ──────────────────────────────────────────────
if (phase == 1) {
  result <- tryCatch({
    devtools::load_all(pkg_dir, quiet = TRUE)
    report(1, "PASS", "load_all() succeeded")
  }, error = function(e) {
    report(1, "FAIL", "load_all() failed", conditionMessage(e))
  })
}

# ── Phase 2: Functions ─────────────────────────────────────────────
if (phase == 2) {
  result <- tryCatch({
    devtools::load_all(pkg_dir, quiet = TRUE)

    desc <- read.dcf(file.path(pkg_dir, "DESCRIPTION"))
    pkg_name <- desc[1, "Package"]

    ns_file <- file.path(pkg_dir, "NAMESPACE")
    if (!file.exists(ns_file)) {
      report(2, "FAIL", "no NAMESPACE file", "Run devtools::document() first")
    } else {
      ns_content <- readLines(ns_file)
      exports <- grep("^export\\(", ns_content, value = TRUE)
      export_names <- gsub("export\\((.+)\\)", "\\1", exports)

      # Check each required export
      missing <- setdiff(REQUIRED_EXPORTS, export_names)
      found <- intersect(REQUIRED_EXPORTS, export_names)

      if (length(missing) > 0) {
        report(2, "FAIL",
               sprintf("%d/%d required exports found", length(found),
                       length(REQUIRED_EXPORTS)),
               paste("Missing:", paste(missing, collapse = ", ")))
      } else {
        # Verify each export actually exists
        truly_missing <- c()
        for (fn in REQUIRED_EXPORTS) {
          if (!exists(fn, envir = asNamespace(pkg_name), inherits = FALSE)) {
            truly_missing <- c(truly_missing, fn)
          }
        }
        if (length(truly_missing) > 0) {
          report(2, "FAIL",
                 sprintf("%d/%d exports callable",
                         length(REQUIRED_EXPORTS) - length(truly_missing),
                         length(REQUIRED_EXPORTS)),
                 paste("Not callable:", paste(truly_missing, collapse = ", ")))
        } else {
          report(2, "PASS",
                 sprintf("all %d required functions exported and callable",
                         length(REQUIRED_EXPORTS)))
        }
      }
    }
  }, error = function(e) {
    report(2, "FAIL", "evaluation error", conditionMessage(e))
  })
}

# ── Phase 3: Documentation ─────────────────────────────────────────
if (phase == 3) {
  result <- tryCatch({
    devtools::document(pkg_dir, quiet = TRUE)

    man_dir <- file.path(pkg_dir, "man")
    if (!dir.exists(man_dir)) {
      report(3, "FAIL", "no man/ directory",
             "devtools::document() did not create man/")
    } else {
      rd_files <- list.files(man_dir, pattern = "\\.Rd$")
      n_docs <- length(rd_files)

      # Check each required function has documentation
      missing_docs <- c()
      for (fn in REQUIRED_EXPORTS) {
        rd_name <- paste0(fn, ".Rd")
        if (!rd_name %in% rd_files) {
          missing_docs <- c(missing_docs, fn)
        }
      }

      if (length(missing_docs) > 0) {
        report(3, "FAIL",
               sprintf("%d/%d required functions documented",
                       length(REQUIRED_EXPORTS) - length(missing_docs),
                       length(REQUIRED_EXPORTS)),
               paste("Missing docs:", paste(missing_docs, collapse = ", ")))
      } else {
        # Check for @return and @examples in R/ files
        r_files <- list.files(file.path(pkg_dir, "R"),
                              pattern = "\\.R$", full.names = TRUE)
        all_code <- unlist(lapply(r_files, readLines))
        has_return <- any(grepl("#'.*@return", all_code))
        has_examples <- any(grepl("#'.*@examples", all_code))

        issues <- c()
        if (!has_return) issues <- c(issues, "missing @return tags")
        if (!has_examples) issues <- c(issues, "missing @examples")

        if (length(issues) > 0) {
          report(3, "FAIL",
                 sprintf("%d docs found", n_docs),
                 paste(issues, collapse = "; "))
        } else {
          report(3, "PASS",
                 sprintf("%d documented functions, all with @return + @examples",
                         n_docs))
        }
      }
    }
  }, error = function(e) {
    report(3, "FAIL", "document() failed", conditionMessage(e))
  })
}

# ── Phase 4: Tests + Coverage ──────────────────────────────────────
if (phase == 4) {
  result <- tryCatch({
    test_dir <- file.path(pkg_dir, "tests", "testthat")
    if (!dir.exists(test_dir)) {
      report(4, "FAIL", "no tests directory", "Run usethis::use_testthat(3)")
    } else {
      test_files <- list.files(test_dir, pattern = "^test-.*\\.R$")
      if (length(test_files) == 0) {
        report(4, "FAIL", "0 test files",
               "Create test files in tests/testthat/")
      } else {
        test_result <- devtools::test(pkg_dir, reporter = "summary")
        n_tests <- sum(vapply(test_result, function(x) length(x$results),
                              integer(1)))
        failures <- sum(vapply(test_result, function(x) {
          sum(vapply(x$results, function(r) {
            inherits(r, "expectation_failure") ||
              inherits(r, "expectation_error")
          }, logical(1)))
        }, integer(1)))

        if (failures > 0) {
          report(4, "FAIL",
                 sprintf("%d/%d tests passed", n_tests - failures, n_tests),
                 sprintf("%d failures", failures))
        } else {
          # Tests pass — check coverage
          coverage_pct <- NA_real_
          cov_msg <- ""
          cov_ok <- TRUE
          tryCatch({
            cov <- covr::package_coverage(pkg_dir, quiet = TRUE)
            coverage_pct <- as.numeric(covr::percent_coverage(cov))
            if (coverage_pct < 80) {
              cov_ok <- FALSE
              cov_msg <- sprintf("coverage %.1f%% < 80%% threshold",
                                 coverage_pct)
            }
          }, error = function(e) {
            # covr not available or fails — skip coverage gate
            cov_msg <<- paste("covr skipped:", conditionMessage(e))
          })

          if (!cov_ok) {
            report(4, "FAIL",
                   sprintf("all %d tests passed, coverage %.1f%%",
                           n_tests, coverage_pct),
                   cov_msg)
          } else {
            score <- sprintf("all %d tests passed", n_tests)
            if (!is.na(coverage_pct)) {
              score <- sprintf("%s, coverage %.1f%%", score, coverage_pct)
            }
            report(4, "PASS", score)
          }
        }
      }
    }
  }, error = function(e) {
    report(4, "FAIL", "test execution error", conditionMessage(e))
  })
}

# ── Phase 5: R CMD check ──────────────────────────────────────────
if (phase == 5) {
  result <- tryCatch({
    check_result <- devtools::check(pkg_dir, quiet = TRUE)
    n_errors <- length(check_result$errors)
    n_warnings <- length(check_result$warnings)
    n_notes <- length(check_result$notes)

    if (n_errors > 0) {
      report(5, "FAIL",
             sprintf("E:%d W:%d N:%d", n_errors, n_warnings, n_notes),
             paste(check_result$errors, collapse = " | "))
    } else if (n_warnings > 0) {
      report(5, "FAIL",
             sprintf("E:%d W:%d N:%d", n_errors, n_warnings, n_notes),
             paste(check_result$warnings, collapse = " | "))
    } else {
      report(5, "PASS",
             sprintf("E:0 W:0 N:%d", n_notes))
    }
  }, error = function(e) {
    report(5, "FAIL", "check() crashed", conditionMessage(e))
  })
}

# ── Phase 6: Polish ────────────────────────────────────────────────
if (phase == 6) {
  issues <- c()

  has_readme <- file.exists(file.path(pkg_dir, "README.md")) ||
    file.exists(file.path(pkg_dir, "README.Rmd"))
  if (!has_readme) issues <- c(issues, "no README")

  if (!file.exists(file.path(pkg_dir, "NEWS.md"))) {
    issues <- c(issues, "no NEWS.md")
  }

  r_files <- list.files(file.path(pkg_dir, "R"),
                        pattern = "\\.R$", full.names = TRUE)
  if (length(r_files) > 0) {
    all_code <- unlist(lapply(r_files, readLines))
    if (!any(grepl("#'.*@examples", all_code))) {
      issues <- c(issues, "no @examples in any function")
    }
  }

  # Check example .mae file exists
  if (!file.exists(file.path(pkg_dir, "inst", "extdata", "example.mae"))) {
    issues <- c(issues, "no inst/extdata/example.mae test fixture")
  }

  if (length(issues) > 0) {
    report(6, "FAIL", paste(issues, collapse = "; "), "")
  } else {
    report(6, "PASS", "README + NEWS.md + examples + test fixture present")
  }
}
