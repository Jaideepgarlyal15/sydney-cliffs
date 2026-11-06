# Small shared helpers: logging, downloads with caching, assertions.

log_step <- function(...) {
  message(format(Sys.time(), "[%H:%M:%S] "), ...)
}

assert_that <- function(cond, msg) {
  if (!isTRUE(cond)) stop(msg, call. = FALSE)
  invisible(TRUE)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
  invisible(path)
}

# Download once into data/, never twice. Returns the local path.
download_cached <- function(url, dest, manual_hint = NULL) {
  ensure_dir(dirname(dest))
  if (file.exists(dest) && file.size(dest) > 0) {
    log_step("cached: ", basename(dest))
    return(dest)
  }
  log_step("downloading: ", basename(dest))
  ok <- tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_user_agent("sydney-cliffs (hackathon research)") |>
      httr2::req_timeout(600) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_perform(path = dest)
    httr2::resp_status(resp) < 400
  }, error = function(e) {
    if (file.exists(dest)) unlink(dest)
    FALSE
  })
  if (!ok || !file.exists(dest) || file.size(dest) == 0) {
    stop(
      "Download failed for ", basename(dest), "\n  URL: ", url,
      if (!is.null(manual_hint)) paste0("\n  ", manual_hint) else "",
      "\n  Save the file manually to: ", dest, call. = FALSE
    )
  }
  dest
}

unzip_once <- function(zip_path, exdir) {
  if (!dir.exists(exdir) || length(list.files(exdir, recursive = TRUE)) == 0) {
    ensure_dir(exdir)
    utils::unzip(zip_path, exdir = exdir)
  }
  exdir
}

find_file <- function(dir, pattern) {
  hits <- list.files(dir, pattern = pattern, recursive = TRUE, full.names = TRUE,
                     ignore.case = TRUE)
  assert_that(length(hits) >= 1,
              paste0("No file matching '", pattern, "' under ", dir))
  hits[[1]]
}

# Percentile rank in [0, 1] of each x within reference values.
percentile_in <- function(x, reference) {
  reference <- sort(reference[is.finite(reference)])
  findInterval(x, reference) / length(reference)
}

# Disjoint-set union over pairs, returns a component id per node 1..n.
connected_components <- function(n, from, to) {
  from <- as.integer(from); to <- as.integer(to)
  parent <- seq_len(n)
  find <- function(i) {
    while (parent[i] != i) {
      parent[i] <<- parent[parent[i]]
      i <- parent[i]
    }
    i
  }
  for (k in seq_along(from)) {
    a <- find(from[k]); b <- find(to[k])
    if (a != b) parent[b] <- a
  }
  vapply(seq_len(n), find, integer(1))
}
