# Advanced analytics on the chosen cliff lines.
#
#  A. Step-vs-slope: is the change across the line a discrete step (logistic)
#     or just a steep part of a smooth gradient (linear)? Judged by BIC on
#     Gaussian maximum likelihood, with a bootstrap over SA1s for uncertainty,
#     plus a local-linear (regression-discontinuity style) jump at the line.
#  C. Change since 2016: did the gap in RELATIVE advantage widen or narrow?
#     Standardised within year (ABS advises against comparing raw SEIFA scores
#     across releases); only SA1s with unchanged boundaries (change_flag "0").
#
# Modules B (multivariate height) and D (edge_pct sensitivity) were dropped for
# time; see RESULTS.md "Methods dropped".

# ---- Transect geometry -----------------------------------------------------------

# Split a (MULTI)LINESTRING into a segment matrix: x1, y1, x2, y2 per row.
line_segment_matrix <- function(geom) {
  xy <- sf::st_coordinates(geom)
  part <- xy[, ncol(xy)]          # last column identifies the part
  segs <- lapply(split(seq_len(nrow(xy)), part), function(idx) {
    m <- xy[idx, 1:2, drop = FALSE]
    if (nrow(m) < 2) return(NULL)
    cbind(m[-nrow(m), 1], m[-nrow(m), 2], m[-1, 1], m[-1, 2], part = part[idx[1]])
  })
  do.call(rbind, Filter(Negate(is.null), segs))
}

# For one point: distance to the nearest segment and the side of that segment
# (sign of the 2D cross product along the segment direction).
nearest_segment_side <- function(px, py, segs) {
  vx <- segs[, 3] - segs[, 1]; vy <- segs[, 4] - segs[, 2]
  wx <- px - segs[, 1];        wy <- py - segs[, 2]
  L2 <- pmax(vx^2 + vy^2, 1e-12)
  tt <- pmin(1, pmax(0, (wx * vx + wy * vy) / L2))
  qx <- segs[, 1] + tt * vx; qy <- segs[, 2] + tt * vy
  d2 <- (px - qx)^2 + (py - qy)^2
  k <- which.min(d2)
  cross <- vx[k] * (py - segs[k, 2]) - vy[k] * (px - segs[k, 1])
  c(dist = sqrt(d2[k]), side = sign(cross), part = segs[k, "part"])
}

# SA1 points within radius_m of a cliff line, with the signed distance d
# (metres, positive on the high side) and the locally standardised outcome z.
# The side is computed two independent ways:
#   side      cluster rule: nearer to the line's hi_unit than its lo_unit SA1s
#   side_geom geometric rule: cross-product side of the nearest line segment,
#             with each line part oriented once so its majority matches `side`
# The two must agree (tested on the synthetic grid); d is signed by `side`.
transect_points <- function(res, line_id, var = "irsad_2021", radius_m = 1500) {
  ln <- res$lines[res$lines$line_id == line_id, ]
  assert_that(nrow(ln) == 1, paste("no cliff line with id", line_id))
  b <- sf::st_drop_geometry(res$borders)
  b <- b[which(b$line_id == line_id), ]
  hi_set <- unique(b$hi_unit); lo_set <- unique(b$lo_unit)

  units <- res$units
  near <- which(lengths(sf::st_is_within_distance(units, ln, dist = radius_m)) > 0)
  cen <- suppressWarnings(sf::st_centroid(sf::st_geometry(units[near, ])))
  xy <- sf::st_coordinates(cen)

  d_hi <- apply(sf::st_distance(cen, units[hi_set, ]), 1, min)
  d_lo <- apply(sf::st_distance(cen, units[lo_set, ]), 1, min)
  side <- ifelse(d_hi <= d_lo, 1L, -1L)

  segs <- line_segment_matrix(sf::st_geometry(ln))
  hits <- t(vapply(seq_len(nrow(xy)),
                   function(i) nearest_segment_side(xy[i, 1], xy[i, 2], segs),
                   c(dist = 0, side = 0, part = 0)))
  side_geom <- hits[, "side"]
  # Orient each line part once: a merged MULTILINESTRING can flip direction
  # between parts, which flips the raw cross-product sign.
  for (p in unique(hits[, "part"])) {
    k <- hits[, "part"] == p & side_geom != 0
    if (any(k) && sum(side[k] * side_geom[k]) < 0) {
      side_geom[hits[, "part"] == p] <- -side_geom[hits[, "part"] == p]
    }
  }
  side_geom[side_geom == 0] <- side[side_geom == 0]   # centroid exactly on the line

  x <- units[[var]][near]
  keep <- is.finite(x)
  z <- (x[keep] - mean(x[keep])) / stats::sd(x[keep])
  data.frame(
    line_id   = line_id,
    sa1_code  = units$sa1_code[near][keep],
    d_m       = hits[keep, "dist"] * side[keep],
    z         = z,
    side      = side[keep],
    side_geom = as.integer(side_geom[keep]),
    raw       = x[keep]
  )
}

# ---- A. Step vs slope -------------------------------------------------------------

# Gaussian ML for both models; BIC counts sigma as a parameter.
#   M1 linear:   z = a + b d          (k = 3)
#   M2 logistic: z = lo + (hi-lo)/(1+exp(-(d-c)/s)), s > 0 fitted as log s (k = 5)
# delta_bic = BIC(M1) - BIC(M2); > 10 is strong evidence of a step.
fit_step_vs_slope <- function(d, z, starts = NULL) {
  n <- length(d)
  m1 <- stats::lm(z ~ d)
  bic1 <- 3 * log(n) - 2 * as.numeric(stats::logLik(m1))

  sse <- function(p) {
    mu <- p[1] + (p[2] - p[1]) / (1 + exp(-(d - p[3]) / exp(p[4])))
    sum((z - mu)^2)
  }
  if (is.null(starts)) {
    lo0 <- mean(z[d < 0]); hi0 <- mean(z[d >= 0])
    starts <- expand.grid(
      c = c(stats::quantile(d, 0.35), 0, stats::quantile(d, 0.65)),
      log_s = log(c(50, 150, 400))
    )
    starts <- lapply(seq_len(nrow(starts)),
                     function(i) c(lo0, hi0, starts$c[i], starts$log_s[i]))
  }
  fits <- lapply(starts, function(p0)
    stats::optim(p0, sse, method = "Nelder-Mead", control = list(maxit = 1000)))
  best <- fits[[which.min(vapply(fits, `[[`, numeric(1), "value"))]]
  sigma2 <- best$value / n
  ll2 <- -n / 2 * (log(2 * pi * sigma2) + 1)
  bic2 <- 5 * log(n) - 2 * ll2
  p <- best$par
  mu2 <- p[1] + (p[2] - p[1]) / (1 + exp(-(d - p[3]) / exp(p[4])))
  list(
    delta_bic = bic1 - bic2,
    s = exp(p[4]),
    width_m = 2 * log(9) * exp(p[4]),   # 10% -> 90% transition
    centre = p[3], lo = p[1], hi = p[2],
    pars = p,
    fit_linear = as.numeric(stats::fitted(m1)),
    fit_logistic = mu2
  )
}

# Local linear jump at d = 0 with a triangular kernel of bandwidth h, fitted
# separately on each side (regression-discontinuity style).
rd_jump <- function(d, z, h) {
  w <- pmax(0, 1 - abs(d) / h)
  hi <- which(d >= 0 & w > 0); lo <- which(d < 0 & w > 0)
  if (length(hi) < 3 || length(lo) < 3) return(NA_real_)
  i_hi <- stats::coef(stats::lm(z ~ d, subset = hi, weights = w))[1]
  i_lo <- stats::coef(stats::lm(z ~ d, subset = lo, weights = w))[1]
  unname(i_hi - i_lo)
}

# Full step-vs-slope analysis of one cliff line.
transect_fit <- function(res, line_id, var = "irsad_2021", radius_m = 1500,
                         bandwidths = c(300, 500, 800), boot_n = 999, seed = 1) {
  pts <- transect_points(res, line_id, var, radius_m)
  n <- nrow(pts)
  empty <- data.frame(line_id = line_id, n_points = n, delta_bic = NA_real_,
                      delta_bic_lo = NA_real_, delta_bic_hi = NA_real_,
                      p_step_boot = NA_real_, width_m = NA_real_, width_lo = NA_real_,
                      width_hi = NA_real_, centre_m = NA_real_,
                      jump_300 = NA_real_, jump_500 = NA_real_,
                      jump_800 = NA_real_, jump_500_lo = NA_real_, jump_500_hi = NA_real_,
                      jump_stable = NA)
  if (n < 10 || sum(pts$d_m >= 0) < 4 || sum(pts$d_m < 0) < 4) {
    return(list(summary = empty, points = pts))
  }

  fit <- fit_step_vs_slope(pts$d_m, pts$z)
  pts$fit_linear <- fit$fit_linear
  pts$fit_logistic <- fit$fit_logistic
  jumps <- vapply(bandwidths, function(h) rd_jump(pts$d_m, pts$z, h), numeric(1))
  names(jumps) <- paste0("jump_", bandwidths)
  jump_stable <- if (all(is.finite(jumps))) {
    (max(jumps) - min(jumps)) / mean(abs(jumps)) < 0.25
  } else NA

  # Bootstrap over SA1s within each side; reduced starts anchored at the fit.
  set.seed(seed)
  hi <- which(pts$d_m >= 0); lo <- which(pts$d_m < 0)
  anchor <- list(fit$pars, fit$pars + c(0, 0, 100, 0), fit$pars + c(0, 0, -100, 0))
  bt <- t(vapply(seq_len(boot_n), function(b) {
    idx <- c(sample(hi, replace = TRUE), sample(lo, replace = TRUE))
    db <- pts$d_m[idx]; zb <- pts$z[idx]
    f <- fit_step_vs_slope(db, zb, starts = anchor)
    c(delta_bic = f$delta_bic, width = f$width_m, jump = rd_jump(db, zb, 500))
  }, numeric(3)))
  ci <- function(x) stats::quantile(x, c(0.025, 0.975), na.rm = TRUE, names = FALSE)
  ci_db <- ci(bt[, "delta_bic"]); ci_w <- ci(bt[, "width"]); ci_j <- ci(bt[, "jump"])

  summary <- data.frame(
    line_id = line_id, n_points = n,
    delta_bic = fit$delta_bic, delta_bic_lo = ci_db[1], delta_bic_hi = ci_db[2],
    p_step_boot = mean(bt[, "delta_bic"] > 0, na.rm = TRUE),
    width_m = fit$width_m, width_lo = ci_w[1], width_hi = ci_w[2],
    centre_m = fit$centre,
    jump_300 = unname(jumps["jump_300"]), jump_500 = unname(jumps["jump_500"]),
    jump_800 = unname(jumps["jump_800"]),
    jump_500_lo = ci_j[1], jump_500_hi = ci_j[2],
    jump_stable = jump_stable
  )
  list(summary = summary, points = pts)
}

# ---- C. Change since 2016 ----------------------------------------------------------

# Population-weighted side gap in standardised IRSAD, per year, per cliff line.
# Standardisation is within year across all eligible analysis SA1s, so only the
# RELATIVE gap is compared, never raw SEIFA scores (per ABS guidance).
gap_change <- function(res, boot_n = 999, seed = 1) {
  u <- sf::st_drop_geometry(res$units)
  eligible <- u$change_flag == "0" & is.finite(u$irsad_2016) & is.finite(u$irsad_2021)
  z16 <- z21 <- rep(NA_real_, nrow(u))
  z16[eligible] <- standardise(u$irsad_2016[eligible])
  z21[eligible] <- standardise(u$irsad_2021[eligible])
  w <- ifelse(is.finite(u$pop), u$pop, 0)

  b <- sf::st_drop_geometry(res$borders)
  set.seed(seed)
  rows <- lapply(sort(unique(b$line_id[!is.na(b$line_id)])), function(id) {
    hi <- unique(b$hi_unit[which(b$line_id == id)])
    lo <- unique(b$lo_unit[which(b$line_id == id)])
    hi <- hi[eligible[hi]]; lo <- lo[eligible[lo]]
    out <- data.frame(line_id = id, gap_2016 = NA_real_, gap_2016_lo = NA_real_,
                      gap_2016_hi = NA_real_, gap_2021 = NA_real_, gap_2021_lo = NA_real_,
                      gap_2021_hi = NA_real_, gap_change = NA_real_,
                      gap_change_lo = NA_real_, gap_change_hi = NA_real_)
    if (length(hi) == 0 || length(lo) == 0) return(out)
    gap <- function(z, hi_i, lo_i)
      stats::weighted.mean(z[hi_i], w[hi_i]) - stats::weighted.mean(z[lo_i], w[lo_i])
    out$gap_2016 <- gap(z16, hi, lo)
    out$gap_2021 <- gap(z21, hi, lo)
    out$gap_change <- out$gap_2021 - out$gap_2016
    if (length(hi) >= 2 && length(lo) >= 2) {
      bt <- t(vapply(seq_len(boot_n), function(k) {
        hi_b <- sample(hi, replace = TRUE); lo_b <- sample(lo, replace = TRUE)
        c(g16 = gap(z16, hi_b, lo_b), g21 = gap(z21, hi_b, lo_b))
      }, c(g16 = 0, g21 = 0)))
      q <- function(x) stats::quantile(x, c(0.025, 0.975), names = FALSE)
      q16 <- q(bt[, "g16"]); q21 <- q(bt[, "g21"]); qch <- q(bt[, "g21"] - bt[, "g16"])
      out$gap_2016_lo <- q16[1]; out$gap_2016_hi <- q16[2]
      out$gap_2021_lo <- q21[1]; out$gap_2021_hi <- q21[2]
      out$gap_change_lo <- qch[1]; out$gap_change_hi <- qch[2]
    }
    out
  })
  do.call(rbind, rows)
}

# ---- Stage entry point --------------------------------------------------------------

# Runs A and C on the given lines, writes out/transects.csv and
# out/transect_points.csv, and returns the summary table for the merge into
# cliffs_top.csv.
run_advanced <- function(res, line_ids, cfg, paths) {
  fits <- lapply(line_ids, function(id) {
    log_step(sprintf("advanced: transect for line %d", id))
    transect_fit(res, id, var = res$var, radius_m = cfg$transect_radius_m,
                 bandwidths = cfg$rd_bandwidths_m, boot_n = cfg$boot_n,
                 seed = cfg$seed + id)
  })
  summary <- do.call(rbind, lapply(fits, `[[`, "summary"))
  points <- do.call(rbind, lapply(fits, function(f) {
    p <- f$points
    for (col in c("fit_linear", "fit_logistic"))     # absent when a line early-exits
      if (!col %in% names(p)) p[[col]] <- NA_real_
    p[, c("line_id", "sa1_code", "d_m", "z", "side", "fit_linear", "fit_logistic")]
  }))
  log_step("advanced: 2016 vs 2021 side gaps")
  chg <- gap_change(res, boot_n = cfg$boot_n, seed = cfg$seed)
  summary <- merge(summary, chg, by = "line_id", all.x = TRUE)

  readr::write_csv(summary, file.path(paths$out, "transects.csv"))
  readr::write_csv(points, file.path(paths$out, "transect_points.csv"))
  summary
}
