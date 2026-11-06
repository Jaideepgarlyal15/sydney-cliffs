# Synthetic SA1-like data with known answers, used by the tests and by
# scripts/demo_synthetic.R. Nothing here is real Sydney data.
#
# A grid of square "SA1s" in GDA2020 / MGA56 near Sydney. The west half is an
# advantaged cluster, the east half a disadvantaged one, so the true cliff is the
# vertical line at x = x0 + step_col * cell. One planted outlier sits deep in the
# east half and must NOT produce a cliff.

make_synthetic_sa1 <- function(nx = 30, ny = 30, cell = 150, step_col = 15,
                               jump = 3, noise = 0.6, outlier = TRUE,
                               pattern = c("step", "gradient"), seed = 1) {
  pattern <- match.arg(pattern)
  set.seed(seed)
  x0 <- 330000; y0 <- 6250000
  polys <- vector("list", nx * ny)
  col <- row <- integer(nx * ny)
  k <- 0
  for (r in seq_len(ny)) for (c in seq_len(nx)) {
    k <- k + 1
    xa <- x0 + (c - 1) * cell; ya <- y0 + (r - 1) * cell
    polys[[k]] <- sf::st_polygon(list(rbind(c(xa, ya), c(xa + cell, ya), c(xa + cell, ya + cell),
                                            c(xa, ya + cell), c(xa, ya))))
    col[k] <- c; row[k] <- r
  }
  base <- switch(pattern,
    step     = ifelse(col <= step_col, jump / 2, -jump / 2),
    gradient = (col - (nx + 1) / 2) / nx * jump
  )
  val <- base + stats::rnorm(length(base), sd = noise)
  outlier_idx <- NA_integer_
  if (outlier) {
    outlier_idx <- which(col == nx - 4 & row == ny %/% 2)
    val[outlier_idx] <- jump * 1.5
  }
  irsad <- 1000 + 100 * val
  sf::st_sf(
    sa1_code    = sprintf("1%010d", seq_along(polys)),
    sa2_name    = ifelse(col <= step_col, "Westside", "Eastside"),
    change_flag = "0",
    resid_share = 1,
    pop         = sample(300:600, length(polys), replace = TRUE),
    irsad_2021  = irsad,
    irsad_2016  = irsad + stats::rnorm(length(irsad), sd = 20),
    hh_income_wk = round(exp(7.4 + 0.3 * val)),
    rent_wk     = round(exp(6.3 + 0.2 * val)),
    median_age  = round(38 + 2 * val),
    col = col, row = row,
    geometry = sf::st_sfc(polys, crs = 7856)
  ) |> structure(true_cliff_x = x0 + step_col * cell, outlier_idx = outlier_idx)
}
