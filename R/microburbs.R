# Microburbs API client (hackathon key). The key is read from the environment
# variable MICROBURBS_API_KEY (set it in .Renviron, which is gitignored).
# Documented behaviour handled explicitly:
#   - 403 outside the City of Sydney coverage area  -> status "outside"
#   - 200 with data = null ("available": false)     -> status "unavailable"
#   - 429 rate limit                                -> retried with backoff
# Raw responses are cached under data/microburbs/ and never committed.

mb_key <- function() {
  k <- Sys.getenv("MICROBURBS_API_KEY")
  assert_that(nzchar(k), "MICROBURBS_API_KEY is not set (copy .Renviron.example to .Renviron)")
  k
}

mb_request <- function(path, query = list(), cfg = cliffs_config(), key = mb_key()) {
  req <- httr2::request(cfg$microburbs_base) |>
    httr2::req_url_path_append(path) |>
    httr2::req_url_query(!!!query) |>
    httr2::req_auth_bearer_token(key) |>
    httr2::req_user_agent("sydney-cliffs (hackathon)") |>
    httr2::req_throttle(rate = cfg$microburbs_rps) |>
    httr2::req_retry(max_tries = 4, is_transient = function(r) httr2::resp_status(r) == 429) |>
    httr2::req_error(is_error = function(r) FALSE)
  resp <- httr2::req_perform(req)
  mb_parse(httr2::resp_status(resp), httr2::resp_body_string(resp))
}

# Pure: status code + body text -> list(status, data).
mb_parse <- function(code, body) {
  if (code == 403) return(list(status = "outside", data = NULL))
  if (code == 429) return(list(status = "rate_limited", data = NULL))
  if (code >= 400) return(list(status = paste0("http_", code), data = NULL))
  js <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  if (is.null(js$data)) return(list(status = "unavailable", data = NULL))
  list(status = "ok", data = js$data)
}

mb_cached <- function(path, query = list(), cache_dir = cliffs_paths()$mb_cache, ...) {
  ensure_dir(cache_dir)
  key <- gsub("[^A-Za-z0-9]+", "_", paste(path, paste(unlist(query), collapse = "_")))
  f <- file.path(cache_dir, paste0(key, ".rds"))
  if (file.exists(f)) return(readRDS(f))
  res <- mb_request(path, query, ...)
  saveRDS(res, f)
  res
}

mb_suburb_market <- function(suburb, ...) {
  mb_cached(paste0("/v1/suburbs/", utils::URLencode(suburb, reserved = TRUE), "/market/all"), ...)
}

mb_suburbs <- function(...) mb_cached("/v1/suburbs/list", ...)
