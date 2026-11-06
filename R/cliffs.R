# Stage 3: LISA clusters and cliff lines.
#
# Definition (agreed with Durand): a cliff is a shared border between an SA1 in a
# significant High-High cluster and an SA1 in a significant Low-Low cluster.
# High-Low / Low-High outliers never form cliffs. Touching cliff borders are
# merged into lines; lines shorter than min_line_m are dropped.

# ---- Transforms ----------------------------------------------------------------

transform_var <- function(x, type = c("score", "log", "logit")) {
  type <- match.arg(type)
  x <- as.numeric(x)
  switch(type,
    score = x,
    log   = ifelse(x > 0, log(x), NA_real_),
    logit = { p <- pmin(pmax(x, 0.005), 0.995); log(p / (1 - p)) }
  )
}

standardise <- function(x) (x - mean(x, na.rm = TRUE)) / stats::sd(x, na.rm = TRUE)

# ---- Graph helpers -------------------------------------------------------------

# Keep only units in keep_idx (logical or integer) and re-index edges to match.
subset_graph <- function(units, edges, keep) {
  keep_idx <- if (is.logical(keep)) which(keep) else keep
  map <- integer(nrow(units)); map[keep_idx] <- seq_along(keep_idx)
  e <- edges[map[edges$i] > 0 & map[edges$j] > 0, ]
  e$i <- map[e$i]; e$j <- map[e$j]
  rownames(e) <- NULL
  list(units = units[keep_idx, ], edges = e, nb = edges_to_nb(e, length(keep_idx)))
}

# ---- LISA ----------------------------------------------------------------------

run_lisa <- function(z, nb, nsim, q, seed) {
  lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
  res <- spdep::localmoran_perm(z, lw, nsim = nsim, zero.policy = TRUE,
                                alternative = "two.sided", iseed = seed)
  p <- res[, "Pr(folded) Sim"]
  quad <- as.character(attr(res, "quadr")$mean)
  island <- vapply(nb, function(v) length(v) == 1 && v[1] == 0L, logical(1))
  p[island] <- NA
  p_fdr <- stats::p.adjust(p, method = "BH")
  label <- ifelse(!is.na(p_fdr) & p_fdr <= q, quad, "ns")
  label <- dplyr::recode(label, "High-High" = "HH", "Low-Low" = "LL",
                         "High-Low" = "HL", "Low-High" = "LH")
  data.frame(Ii = res[, "Ii"], p = p, p_fdr = p_fdr, label = label)
}

# Global Moran's I, used for reporting and for calibrating the null.
global_moran <- function(z, nb) {
  lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
  unname(spdep::moran(z, lw, n = length(z), S0 = spdep::Szero(lw), zero.policy = TRUE)$I)
}

# ---- Cliff detection -------------------------------------------------------------

# Each border (i, j) splits its neighbourhood into two sides:
#   side_i = {i} + neighbours of i, minus {j} and the neighbours of j
#   side_j = the same the other way round
# The side gap compares the two side means. A single odd SA1 cannot produce a
# large side gap because its side is averaged with its ordinary neighbours.
side_gaps <- function(z, nb, i, j) {
  vapply(seq_along(i), function(k) {
    a <- i[k]; b <- j[k]
    na <- c(a, nb[[a]][nb[[a]] > 0]); nbb <- c(b, nb[[b]][nb[[b]] > 0])
    sa <- setdiff(na, nbb); sb <- setdiff(nbb, na)
    if (!length(sa)) sa <- a
    if (!length(sb)) sb <- b
    mean(z[sa]) - mean(z[sb])
  }, numeric(1))
}

# Cluster support: the high side holds an SA1 in a significant High-High cluster
# and the low side one in a significant Low-Low cluster (Durand's rule).
side_support <- function(label, nb, hi, lo) {
  vapply(seq_along(hi), function(k) {
    a <- hi[k]; b <- lo[k]
    sa <- setdiff(c(a, nb[[a]][nb[[a]] > 0]), b)
    sb <- setdiff(c(b, nb[[b]][nb[[b]] > 0]), a)
    any(label[sa] == "HH") && any(label[sb] == "LL")
  }, logical(1))
}

# units: sf with a column named `var`; edges from build_edges() on the same rows.
# A border is a cliff border when
#   (1) its side gap is in the top (1 - edge_pct) of all borders, and
#   (2) the high side has a significant HH SA1 and the low side a significant LL SA1.
# LISA uses contiguity up to order `lisa_order`, which gives each SA1 enough
# neighbours for the permutation test to have power after FDR correction.
find_cliffs <- function(units, edges, var, type = "score",
                        nsim = 9999, q = 0.05, min_line_m = 400, seed = 1,
                        edge_pct = 0.95, lisa_order = 2, line_gap_m = 150) {
  x <- transform_var(units[[var]], type)
  g <- subset_graph(units, edges, is.finite(x))
  z <- standardise(x[is.finite(x)])

  nb_lisa <- if (lisa_order > 1) {
    spdep::nblag_cumul(spdep::nblag(g$nb, lisa_order))
  } else g$nb
  lab <- run_lisa(z, nb_lisa, nsim = nsim, q = q, seed = seed)

  e <- g$edges
  e$gap <- abs(z[e$i] - z[e$j])
  sg <- side_gaps(z, g$nb, e$i, e$j)
  e$side_gap <- abs(sg)
  e$gap_pct <- percentile_in(e$side_gap, e$side_gap)
  hi <- ifelse(sg >= 0, e$i, e$j)
  lo <- ifelse(sg >= 0, e$j, e$i)
  cand <- which(e$gap_pct >= edge_pct)
  ok <- rep(FALSE, nrow(e))
  if (length(cand)) ok[cand] <- side_support(lab$label, g$nb, hi[cand], lo[cand])

  borders <- e[ok, ]
  if (nrow(borders) > 0) {
    raw <- units[[var]][is.finite(x)]
    borders$hi_unit <- hi[ok]; borders$lo_unit <- lo[ok]
    borders$hi_value <- raw[hi[ok]]; borders$lo_value <- raw[lo[ok]]
  }

  lines <- merge_cliff_lines(borders, g$units, min_line_m, line_gap_m)
  if (nrow(borders) > 0) {
    hit <- sf::st_is_within_distance(borders, lines, dist = 1)
    borders$line_id <- vapply(hit, function(v) if (length(v)) lines$line_id[v[1]] else NA_integer_, integer(1))
  }

  list(
    labels  = cbind(sf::st_drop_geometry(g$units), lab, z = z),
    units   = g$units,
    edges   = g$edges,
    borders = borders,
    lines   = lines,
    moran_I = global_moran(z, g$nb),
    n_units = nrow(g$units),
    var = var
  )
}

# Merge cliff borders into lines and score them. Borders within line_gap_m of each
# other belong to the same cliff, so one noisy border does not split a cliff in two.
merge_cliff_lines <- function(borders, units, min_line_m, line_gap_m = 0) {
  empty <- sf::st_sf(line_id = integer(), length_m = numeric(), n_borders = integer(),
                     gap_pct = numeric(), gap = numeric(), score = numeric(),
                     hi_value = numeric(), lo_value = numeric(),
                     hi_area = character(), lo_area = character(),
                     geometry = sf::st_sfc(crs = sf::st_crs(units)))
  if (is.null(borders) || nrow(borders) == 0) return(empty)

  touch <- if (line_gap_m > 0) sf::st_is_within_distance(borders, dist = line_gap_m)
           else sf::st_intersects(borders)
  from <- rep(seq_along(touch), lengths(touch)); to <- unlist(touch)
  comp <- connected_components(nrow(borders), from, to)

  area_name <- if ("sa2_name" %in% names(units)) units$sa2_name else rep(NA_character_, nrow(units))
  pieces <- lapply(split(seq_len(nrow(borders)), comp), function(idx) {
    b <- borders[idx, ]
    geom <- sf::st_line_merge(sf::st_cast(sf::st_union(sf::st_geometry(b)), "MULTILINESTRING"))
    w <- b$border_m
    mode_name <- function(u) {
      v <- area_name[u]; v <- v[!is.na(v)]
      if (length(v) == 0) NA_character_ else names(sort(table(v), decreasing = TRUE))[1]
    }
    sf::st_sf(
      length_m  = sum(w),
      n_borders = length(idx),
      gap_pct   = stats::median(b$gap_pct),
      gap       = stats::weighted.mean(b$gap, w),
      hi_value  = stats::weighted.mean(b$hi_value, w),
      lo_value  = stats::weighted.mean(b$lo_value, w),
      hi_area   = mode_name(b$hi_unit),
      lo_area   = mode_name(b$lo_unit),
      geometry  = geom
    )
  })
  lines <- do.call(rbind, pieces)
  lines <- lines[lines$length_m >= min_line_m, ]
  if (nrow(lines) == 0) return(empty)
  lines$score <- lines$gap_pct * log(lines$length_m)
  lines <- lines[order(-lines$score), ]
  lines$line_id <- seq_len(nrow(lines))
  rownames(lines) <- NULL
  lines[, c("line_id", "length_m", "n_borders", "gap_pct", "gap", "score",
            "hi_value", "lo_value", "hi_area", "lo_area")]
}
