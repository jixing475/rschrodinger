#' Read Maestro (.mae/.maegz) Files
#'
#' Parse Schrodinger Maestro format files natively in R without requiring
#' a Schrodinger installation. Extracts CT (Connection Table) level
#' properties into a tidy tibble.
#'
#' @param path Character. Path to a `.mae` or `.maegz` file, or a directory
#'   (reads all `.mae`/`.maegz` files in it).
#' @param properties Character vector or `NULL`. If specified, only extract
#'   these properties (matched after prefix stripping if `strip_prefix` is
#'   `TRUE`). `NULL` extracts all CT-level properties.
#' @param strip_prefix Logical. If `TRUE` (default), strip m2io type and
#'   namespace prefixes from property names (e.g., `r_i_glide_gscore`
#'   becomes `glide_gscore`).
#' @param include_atoms Logical. If `TRUE`, include atom data as a
#'   list-column named `atoms`. Default is `FALSE`.
#'
#' @return A tibble where each row is one CT (Connection Table) entry.
#'   Columns are the extracted properties, plus `_ct_index` (integer)
#'   and `_source_file` (character) tracking provenance.
#'
#' @examples
#' mae_file <- system.file("extdata", "example.mae",
#'   package = "rschrodinger", mustWork = TRUE)
#' read_mae_fast(mae_file)
#'
#' @export
read_mae_fast <- function(
    path,
    properties = NULL,
    strip_prefix = TRUE,
    include_atoms = FALSE
) {
    # Validate input
    if (!is.character(path) || length(path) != 1) {
        cli::cli_abort("{.arg path} must be a single character string.")
    }

    if (!file.exists(path)) {
        cli::cli_abort("Path does not exist: {.path {path}}")
    }

    # If directory, find all .mae/.maegz files

    if (dir.exists(path)) {
        files <- list.files(
            path,
            pattern = "\\.(mae|maegz)$",
            full.names = TRUE,
            recursive = FALSE
        )
        if (length(files) == 0) {
            cli::cli_abort("No .mae or .maegz files found in {.path {path}}")
        }
        cli::cli_inform("Found {length(files)} .mae/.maegz file{?s}.")
        results <- lapply(files, \(f) {
            parse_mae_file(
                f,
                properties = properties,
                strip_prefix = strip_prefix,
                include_atoms = include_atoms
            )
        })
        return(do.call(rbind, results))
    }

    # Single file
    parse_mae_file(
        path,
        properties = properties,
        strip_prefix = strip_prefix,
        include_atoms = include_atoms
    )
}


#' Parse a single .mae/.maegz file
#'
#' @param file_path Path to the file.
#' @param properties Properties to extract (or NULL for all).
#' @param strip_prefix Whether to strip prefixes.
#' @param include_atoms Whether to include atom data.
#'
#' @return A tibble of CT entries.
#' @noRd
parse_mae_file <- function(
    file_path,
    properties = NULL,
    strip_prefix = TRUE,
    include_atoms = FALSE
) {
    # Read lines — handle .maegz via gzfile
    is_gz <- grepl("\\.maegz$", file_path, ignore.case = TRUE)
    if (is_gz) {
        con <- gzfile(file_path, "r")
        on.exit(close(con), add = TRUE)
        lines <- readLines(con, warn = FALSE)
    } else {
        lines <- readLines(file_path, warn = FALSE)
    }

    # Trim whitespace
    lines_trimmed <- trimws(lines)
    n_lines <- length(lines_trimmed)

    # State machine
    ct_list <- list()
    ct_index <- 0L
    i <- 1L

    while (i <= n_lines) {
        line <- lines_trimmed[i]

        # Detect CT block start: "f_m_ct {"
        if (grepl("^f_m_ct\\s*\\{", line)) {
            ct_index <- ct_index + 1L
            ct_result <- parse_ct_block(lines_trimmed, i, include_atoms)
            ct_data <- ct_result$data
            ct_data[["_ct_index"]] <- ct_index
            ct_data[["_source_file"]] <- basename(file_path)
            ct_list[[ct_index]] <- ct_data
            i <- ct_result$end_line + 1L
            next
        }

        i <- i + 1L
    }

    if (length(ct_list) == 0) {
        cli::cli_warn("No CT blocks found in {.path {file_path}}")
        return(tibble::tibble(
            `_ct_index` = integer(),
            `_source_file` = character()
        ))
    }

    # Combine all CTs — they may have different columns
    result <- bind_ct_rows(ct_list)

    # Strip prefixes if requested
    if (strip_prefix) {
        names(result) <- vapply(names(result), strip_mae_prefix, character(1))
    }

    # Filter properties if specified
    if (!is.null(properties)) {
        # Always keep meta columns
        meta_cols <- c("_ct_index", "_source_file", "ct_index", "source_file")
        keep <- intersect(
            c(meta_cols, properties),
            names(result)
        )
        if (length(setdiff(properties, names(result))) > 0) {
            missing <- setdiff(properties, names(result))
            cli::cli_warn("Requested properties not found: {.val {missing}}")
        }
        result <- result[, keep, drop = FALSE]
    }

    result
}


#' Parse a single CT block
#'
#' @param lines_trimmed All lines of the file, trimmed.
#' @param start_line Line index where "f_m_ct {" was found.
#' @param include_atoms Whether to include atom data.
#'
#' @return A list with `data` (named list of CT properties) and
#'   `end_line` (line index of closing `}`).
#' @noRd
parse_ct_block <- function(lines_trimmed, start_line, include_atoms) {
    n_lines <- length(lines_trimmed)
    i <- start_line + 1L # skip the "f_m_ct {" line

    # Phase 1: Collect CT-level property names (before :::)
    prop_names <- character()
    while (i <= n_lines) {
        line <- lines_trimmed[i]
        if (line == ":::") {
            i <- i + 1L
            break
        }
        if (nzchar(line) && !startsWith(line, "#")) {
            prop_names <- c(prop_names, line)
        }
        i <- i + 1L
    }

    # Phase 2: Collect CT-level property values (after :::, before sub-blocks)
    prop_values <- character()
    value_count <- 0L
    n_props <- length(prop_names)

    while (i <= n_lines && value_count < n_props) {
        line <- lines_trimmed[i]

        # Check if we hit a sub-block (m_atom, m_bond, etc.) or closing brace
        if (grepl("^m_\\w+\\[\\d+\\]\\s*\\{", line) || line == "}") {
            break
        }

        # Parse this line as a value
        val <- parse_mae_value(line)
        prop_values <- c(prop_values, val)
        value_count <- value_count + 1L
        i <- i + 1L
    }

    # Build the CT data as a named list
    ct_data <- as.list(stats::setNames(
        prop_values,
        prop_names[seq_along(prop_values)]
    ))

    # Type-convert based on prefix
    ct_data <- type_convert_mae(ct_data)

    # Phase 3: Handle sub-blocks (m_atom, m_bond, etc.)
    atom_data <- NULL
    depth <- 1L # we're inside f_m_ct { already

    while (i <= n_lines && depth > 0) {
        line <- lines_trimmed[i]

        if (line == "}") {
            depth <- depth - 1L
            i <- i + 1L
            next
        }

        # Detect indexed sub-block: m_atom[N] {
        if (grepl("^m_\\w+\\[\\d+\\]\\s*\\{", line) && include_atoms) {
            block_name <- sub("^(m_\\w+)\\[.*", "\\1", line)
            if (block_name == "m_atom") {
                atom_result <- parse_indexed_block(lines_trimmed, i)
                atom_data <- atom_result$data
                i <- atom_result$end_line + 1L
                next
            }
        }

        # Skip non-atom sub-blocks by tracking braces
        if (grepl("\\{\\s*$", line)) {
            depth <- depth + 1L
        }

        i <- i + 1L
    }

    if (include_atoms && !is.null(atom_data)) {
        ct_data[["atoms"]] <- list(atom_data)
    }

    list(data = ct_data, end_line = i - 1L)
}


#' Parse an indexed block (m_atom[N], m_bond[M], etc.)
#'
#' @param lines_trimmed Trimmed lines.
#' @param start_line Line where the block header is.
#'
#' @return A list with `data` (tibble) and `end_line`.
#' @noRd
parse_indexed_block <- function(lines_trimmed, start_line) {
    n_lines <- length(lines_trimmed)
    header <- lines_trimmed[start_line]

    # Extract count from m_atom[N]
    n_entries <- as.integer(sub(".*\\[(\\d+)\\].*", "\\1", header))

    i <- start_line + 1L

    # Collect column names (skip comments, stop at :::)
    col_names <- character()
    while (i <= n_lines) {
        line <- lines_trimmed[i]
        if (line == ":::") {
            i <- i + 1L
            break
        }
        if (nzchar(line) && !startsWith(line, "#")) {
            col_names <- c(col_names, line)
        }
        i <- i + 1L
    }

    # Read data rows until ::: or }
    data_lines <- character()
    row_count <- 0L
    while (i <= n_lines && row_count < n_entries) {
        line <- lines_trimmed[i]
        if (line == ":::" || line == "}") {
            break
        }
        if (nzchar(line)) {
            data_lines <- c(data_lines, lines[i])
            row_count <- row_count + 1L
        }
        i <- i + 1L
    }

    # Skip to closing ::: and }
    while (i <= n_lines && lines_trimmed[i] != "}") {
        i <- i + 1L
    }

    # Parse data lines into a data frame
    # First column is always the atom index
    all_col_names <- c("_index", col_names)

    # Use a simple approach: split each line by whitespace, respecting quotes
    if (length(data_lines) > 0) {
        parsed <- lapply(data_lines, split_mae_data_line)
        # Pad to same length
        max_cols <- max(vapply(parsed, length, integer(1)))
        parsed <- lapply(parsed, \(x) {
            if (length(x) < max_cols) {
                c(x, rep(NA_character_, max_cols - length(x)))
            } else {
                x
            }
        })
        mat <- do.call(rbind, parsed)
        df <- tibble::as_tibble(
            as.data.frame(mat, stringsAsFactors = FALSE),
            .name_repair = "minimal"
        )
        if (ncol(df) <= length(all_col_names)) {
            names(df) <- all_col_names[seq_len(ncol(df))]
        }
    } else {
        df <- tibble::tibble()
    }

    list(data = df, end_line = i)
}


#' Split a .mae data line respecting quoted strings
#'
#' @param line A single data line.
#' @return Character vector of fields.
#' @noRd
split_mae_data_line <- function(line) {
    # Handle quoted strings and <> (empty/NA markers)
    tokens <- character()
    chars <- strsplit(line, "")[[1]]
    n <- length(chars)
    pos <- 1L
    in_quote <- FALSE
    current <- ""

    while (pos <= n) {
        ch <- chars[pos]

        if (in_quote) {
            if (ch == "\"") {
                in_quote <- FALSE
                tokens <- c(tokens, current)
                current <- ""
            } else {
                current <- paste0(current, ch)
            }
        } else {
            if (ch == "\"") {
                in_quote <- TRUE
                current <- ""
            } else if (ch == " " || ch == "\t") {
                if (nzchar(current)) {
                    tokens <- c(tokens, current)
                    current <- ""
                }
            } else {
                current <- paste0(current, ch)
            }
        }
        pos <- pos + 1L
    }

    if (nzchar(current)) {
        tokens <- c(tokens, current)
    }

    tokens
}


#' Parse a single .mae property value
#'
#' Handles quoted strings, <> (NA), and bare values.
#'
#' @param line A trimmed line containing a single value.
#' @return Character string (type conversion happens later).
#' @noRd
parse_mae_value <- function(line) {
    # Remove surrounding quotes
    if (startsWith(line, "\"") && endsWith(line, "\"")) {
        return(substr(line, 2, nchar(line) - 1))
    }
    # <> means NA/empty
    if (line == "<>") {
        return(NA_character_)
    }
    line
}


#' Type-convert a named list of .mae properties based on name prefixes
#'
#' Type prefixes in .mae: s_ = string, r_ = real, i_ = integer, b_ = boolean.
#'
#' @param props Named list of character values.
#' @return Named list with typed values.
#' @noRd
type_convert_mae <- function(props) {
    for (nm in names(props)) {
        val <- props[[nm]]
        if (is.na(val)) {
            next
        }

        if (startsWith(nm, "r_")) {
            props[[nm]] <- as.numeric(val)
        } else if (startsWith(nm, "i_")) {
            props[[nm]] <- as.integer(val)
        } else if (startsWith(nm, "b_")) {
            props[[nm]] <- as.logical(as.integer(val))
        }
        # s_ stays as character
    }
    props
}


#' Strip m2io type and namespace prefixes from a property name
#'
#' E.g., `r_i_glide_gscore` -> `glide_gscore`,
#'        `s_m_title` -> `title`,
#'        `i_m_ct_format` -> `ct_format`.
#'
#' Internal columns starting with `_` are preserved as-is.
#'
#' @param name A property name.
#' @return The stripped name.
#' @noRd
strip_mae_prefix <- function(name) {
    # Don't touch meta columns
    if (startsWith(name, "_")) {
        return(name)
    }

    # Pattern: type_namespace_rest (e.g., r_i_glide_gscore, s_m_title)
    # type = [sirbx], namespace = [a-z]+
    if (grepl("^[sirbx]_[a-zA-Z]+_", name)) {
        # Remove first two segments: type_namespace_
        stripped <- sub("^[sirbx]_[a-zA-Z]+_", "", name)
        if (nzchar(stripped)) return(stripped)
    }

    name
}


#' Bind CT rows with potentially different columns
#'
#' @param ct_list List of named lists (one per CT).
#' @return A tibble.
#' @noRd
bind_ct_rows <- function(ct_list) {
    # Collect all unique column names
    all_names <- unique(unlist(lapply(ct_list, names)))

    # Build each row as a one-row tibble
    rows <- lapply(ct_list, \(ct) {
        row <- vector("list", length(all_names))
        names(row) <- all_names
        for (nm in all_names) {
            if (nm %in% names(ct)) {
                row[[nm]] <- ct[[nm]]
            } else {
                row[[nm]] <- NA
            }
        }
        tibble::as_tibble(row)
    })

    do.call(rbind, rows)
}
