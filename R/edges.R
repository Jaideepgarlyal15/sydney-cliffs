# Stage 2: neighbour pairs with their shared border as a line.
# Two SA1s are neighbours when their boundaries share a line of at least
# min_border_m metres. Corner-only touches have zero length and drop out, so this
# is rook contiguity measured on the ground rather than by vertex matching.
# All pairs are computed in one vectorised GEOS pass (fast on ~12k SA1s).

build_edges <- function(units, min_border_m) {
  assert_that(inherits(units, "sf"), "units must be an sf object")
  assert_that(!sf::st_is_longlat(units), "units must be in a projected (metric) CRS")
  b <- sf::st_sf(id = seq_len(nrow(units)), geometry = sf::st_boundary(sf::st_geometry(units)))
  x <- suppressWarnings(sf::st_intersection(b, b))
  x <- x[x$id < x$id.1, ]
  if (nrow(x) > 0) {
    x <- suppressWarnings(sf::st_collection_extract(x, "LINESTRING"))
  }
  x$len <- as.numeric(sf::st_length(x))
  x <- x[x$len > 0, ]

  # One row per pair: a pair can come back as several line pieces.
  if (nrow(x) > 0) {
    key <- paste(x$id, x$id.1)
    first <- !duplicated(key)
    agg_len <- tapply(x$len, key, sum)
    pieces <- split(sf::st_geometry(x), key)
    geom <- lapply(pieces, function(g) {
      if (length(g) == 1) return(g[[1]])  # common case: one shared line, no merge needed
      sf::st_line_merge(sf::st_cast(sf::st_union(g), "MULTILINESTRING"))[[1]]
    })
    edges <- sf::st_sf(
      i = x$id[first], j = x$id.1[first], border_m = as.numeric(agg_len[key[first]]),
      geometry = sf::st_sfc(geom[key[first]], crs = sf::st_crs(units))
    )
  } else {
    edges <- sf::st_sf(i = integer(), j = integer(), border_m = numeric(),
                       geometry = sf::st_sfc(crs = sf::st_crs(units)))
  }
  edges <- edges[edges$border_m >= min_border_m, ]
  rownames(edges) <- NULL
  list(edges = edges, nb = edges_to_nb(edges, nrow(units)))
}

# Rebuild a symmetric spdep nb object from the kept edges.
edges_to_nb <- function(edges, n) {
  nb <- vector("list", n)
  for (k in seq_len(nrow(edges))) {
    a <- edges$i[k]; b <- edges$j[k]
    nb[[a]] <- c(nb[[a]], b)
    nb[[b]] <- c(nb[[b]], a)
  }
  nb <- lapply(nb, function(v) if (is.null(v)) 0L else sort(as.integer(v)))
  class(nb) <- "nb"
  attr(nb, "region.id") <- as.character(seq_len(n))
  attr(nb, "type") <- "rook-border"
  attr(nb, "sym") <- TRUE
  nb
}

n_islands <- function(nb) sum(vapply(nb, function(v) length(v) == 1 && v[1] == 0L, logical(1)))
