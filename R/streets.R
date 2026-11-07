# Stage 4: what physically runs along each cliff? (road, railway, water, park)
# Uses the public Overpass API (OpenStreetMap, ODbL). Responses are cached in
# data/osm/ so reruns are offline and the API is not hammered.

overpass_ql <- function(bbox) {
  b <- sprintf("%.6f,%.6f,%.6f,%.6f", bbox["ymin"], bbox["xmin"], bbox["ymax"], bbox["xmax"])
  paste0(
    "[out:json][timeout:60];(",
    "way[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street)$\"](", b, ");",
    "way[\"railway\"~\"^(rail|light_rail|subway)$\"](", b, ");",
    "way[\"waterway\"](", b, ");",
    "way[\"natural\"=\"water\"](", b, ");",
    "way[\"leisure\"=\"park\"](", b, ");",
    ");out geom;"
  )
}

# Pure: Overpass JSON (as parsed list) -> sf LINESTRINGs with kind and name.
parse_overpass <- function(js) {
  els <- js$elements
  if (length(els) == 0) {
    return(sf::st_sf(kind = character(), name = character(),
                     geometry = sf::st_sfc(crs = 4326)))
  }
  rows <- lapply(els, function(e) {
    if (is.null(e$geometry) || length(e$geometry) < 2) return(NULL)
    xy <- do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat)))
    t <- e$tags
    kind <- if (!is.null(t$railway)) "rail"
      else if (!is.null(t$highway)) "road"
      else if (!is.null(t$waterway) || identical(t$natural, "water")) "water"
      else if (identical(t$leisure, "park")) "park"
      else "other"
    nm <- if (!is.null(t$name)) t$name else NA_character_
    list(kind = kind, name = nm, geom = sf::st_linestring(xy))
  })
  rows <- Filter(Negate(is.null), rows)
  sf::st_sf(
    kind = vapply(rows, `[[`, "", "kind"),
    name = vapply(rows, function(r) r$name %||% NA_character_, ""),
    geometry = sf::st_sfc(lapply(rows, `[[`, "geom"), crs = 4326)
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

fetch_overpass <- function(bbox, cache_dir, url) {
  ensure_dir(cache_dir)
  key <- gsub("[^0-9]", "", sprintf("%.4f_%.4f_%.4f_%.4f", bbox[1], bbox[2], bbox[3], bbox[4]))
  f <- file.path(cache_dir, paste0(key, ".json"))
  if (!file.exists(f)) {
    resp <- httr2::request(url) |>
      httr2::req_user_agent("sydney-cliffs (hackathon research)") |>
      httr2::req_body_form(data = overpass_ql(bbox)) |>
      # The public server answers 502/504 when busy; treat those as transient too.
      httr2::req_retry(max_tries = 4, backoff = function(i) 5 * i,
                       is_transient = function(r)
                         httr2::resp_status(r) %in% c(429, 502, 503, 504)) |>
      httr2::req_throttle(rate = 1 / 2) |>
      httr2::req_perform()
    writeLines(httr2::resp_body_string(resp), f)
  }
  jsonlite::fromJSON(f, simplifyVector = FALSE)
}

# For each cliff line: the OSM feature with the most length inside a 30 m buffer.
classify_lines <- function(lines, cfg, cache_dir, fetch = fetch_overpass) {
  if (nrow(lines) == 0) return(transform(lines, border_kind = character(),
                                         border_name = character(), border_cover = numeric()))
  out <- lapply(seq_len(nrow(lines)), function(k) {
    ln  <- lines[k, ]
    buf <- sf::st_buffer(sf::st_geometry(ln), 30)
    bb  <- sf::st_bbox(sf::st_transform(buf, 4326))
    osm <- parse_overpass(fetch(bb, cache_dir, cfg$overpass_url))
    if (nrow(osm) == 0) return(data.frame(border_kind = "none", border_name = NA, border_cover = 0))
    osm <- sf::st_transform(osm, sf::st_crs(lines))
    inside <- suppressWarnings(sf::st_intersection(osm, buf))
    if (nrow(inside) == 0) return(data.frame(border_kind = "none", border_name = NA, border_cover = 0))
    inside$len <- as.numeric(sf::st_length(inside))
    agg <- stats::aggregate(len ~ kind + name, data = transform(
      sf::st_drop_geometry(inside), name = ifelse(is.na(name), "(unnamed)", name)), FUN = sum)
    best <- agg[which.max(agg$len), ]
    data.frame(border_kind = best$kind,
               border_name = ifelse(best$name == "(unnamed)", NA, best$name),
               border_cover = min(1, best$len / ln$length_m))
  })
  cbind(lines, do.call(rbind, out))
}
