# Stage 6: a self-contained 3D map per cliff, for screen recording at 1080 x 1920.
# Areas are extruded by their percentile on the variable, so the cliff reads as a
# wall. deck.gl and MapLibre load from a CDN when the page is opened (no R package
# needed). Open out/maps/cliff_<id>.html in Chrome; add ?vertical to get a 9:16 frame.

geojson_text <- function(x) {
  f <- tempfile(fileext = ".geojson")
  on.exit(unlink(f))
  sf::st_write(sf::st_transform(x, 4326), f, driver = "GeoJSON", quiet = TRUE,
               layer_options = "COORDINATE_PRECISION=6")
  paste(readLines(f, warn = FALSE), collapse = "")
}

line_bearing <- function(line) {
  xy <- sf::st_coordinates(sf::st_transform(line, 4326))
  d <- xy[nrow(xy), 1:2] - xy[1, 1:2]
  # Camera looks perpendicular to the cliff so the wall faces the viewer.
  (atan2(d[1], d[2]) * 180 / pi + 90) %% 360
}

write_cliff_map <- function(res, line_id, out_file, title, subtitle, value_label,
                            big_number = "", radius_m = 1500, height_m = 1200) {
  ln <- res$lines[res$lines$line_id == line_id, ]
  assert_that(nrow(ln) == 1, paste("no cliff line with id", line_id))
  units <- res$units
  units$value <- res$labels$z
  units$label <- res$labels$label
  near <- units[lengths(sf::st_is_within_distance(units, ln, dist = radius_m)) > 0, ]
  near$h <- percentile_in(near$value, units$value) * height_m

  centre <- sf::st_coordinates(sf::st_centroid(sf::st_transform(sf::st_geometry(ln), 4326)))
  code_root <- getOption("cliffs.code_root", getOption("cliffs.root", "."))
  tpl <- paste(readLines(file.path(code_root, "R", "map_template.html"), warn = FALSE),
               collapse = "\n")
  html <- tpl
  subs <- list(
    "__AREAS__" = geojson_text(near[, c("h", "label")]),
    "__LINE__"  = geojson_text(ln[, "line_id"]),
    "__LON__"   = sprintf("%.6f", centre[1]),
    "__LAT__"   = sprintf("%.6f", centre[2]),
    "__BEARING__" = sprintf("%.1f", line_bearing(ln)),
    "__TITLE__" = htmlEscape(title),
    "__SUBTITLE__" = htmlEscape(subtitle),
    "__VALUE_LABEL__" = htmlEscape(value_label),
    "__BIG_NUMBER__" = htmlEscape(big_number)
  )
  for (k in names(subs)) html <- gsub(k, subs[[k]], html, fixed = TRUE)
  ensure_dir(dirname(out_file))
  writeLines(html, out_file)
  invisible(out_file)
}

htmlEscape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
