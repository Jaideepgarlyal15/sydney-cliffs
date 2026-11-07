# The method must find a planted cliff, ignore a planted outlier, and find no
# cliff on a smooth gradient. These are the three things a reviewer will ask.

s  <- make_synthetic_sa1()
eg <- build_edges(s, 50)
r  <- find_cliffs(s, eg$edges, "irsad_2021", "score", nsim = 999, q = 0.05,
                  min_line_m = 400, seed = 1)

test_that("edges are rook contiguity with measured border length", {
  expect_equal(nrow(eg$edges), 2 * 30 * 29)          # rook pairs on a 30 x 30 grid
  expect_true(all(abs(eg$edges$border_m - 150) < 1e-6))
  expect_equal(n_islands(eg$nb), 0)
})

test_that("min_border_m drops short borders", {
  expect_equal(nrow(build_edges(s, 200)$edges), 0)
})

test_that("LISA recovers the two planted clusters", {
  west <- s$col <= 15
  expect_gt(mean(r$labels$label[west] == "HH"), 0.8)
  expect_gt(mean(r$labels$label[!west] == "LL"), 0.8)
})

test_that("the planted cliff is found, in the right place, at near full length", {
  expect_gte(nrow(r$lines), 1)
  bb <- sf::st_bbox(r$lines[1, ])
  expect_equal(unname(bb["xmin"]), attr(s, "true_cliff_x"), tolerance = 1)
  expect_equal(unname(bb["xmax"]), attr(s, "true_cliff_x"), tolerance = 1)
  expect_gt(r$lines$length_m[1], 0.9 * 30 * 150)
  expect_gt(r$lines$hi_value[1], r$lines$lo_value[1])
  expect_equal(r$lines$hi_area[1], "Westside")
})

test_that("a single outlier never forms a cliff", {
  o <- attr(s, "outlier_idx")
  expect_true(r$labels$label[o] %in% c("HL", "ns"))
  near_outlier <- lengths(sf::st_is_within_distance(r$lines, s[o, ], dist = 1)) > 0
  expect_false(any(near_outlier))
})

test_that("a smooth gradient produces no cliff line", {
  sg <- make_synthetic_sa1(pattern = "gradient", outlier = FALSE, seed = 2)
  rg <- find_cliffs(sg, build_edges(sg, 50)$edges, "irsad_2021", "score",
                    nsim = 999, q = 0.05, min_line_m = 400, seed = 1)
  expect_equal(nrow(rg$lines), 0)
})

test_that("results are reproducible with the same seed", {
  r2 <- find_cliffs(s, eg$edges, "irsad_2021", "score", nsim = 999, q = 0.05,
                    min_line_m = 400, seed = 1)
  expect_identical(r$labels$label, r2$labels$label)
  expect_equal(r$lines$score, r2$lines$score)
})

test_that("SAR surrogates are calibrated to the observed Moran's I", {
  rho <- calibrate_rho(r$edges |> edges_to_nb(nrow(r$units)), r$moran_I, seed = 3)
  Y <- sar_surrogate(edges_to_nb(r$edges, nrow(r$units)), rho, 5, seed = 4)
  I_sim <- mean(apply(Y, 2, global_moran, nb = edges_to_nb(r$edges, nrow(r$units))))
  expect_equal(I_sim, r$moran_I, tolerance = 0.05)
})

test_that("the planted cliff beats every surrogate (max-statistic null)", {
  cfg <- cliffs_config(); cfg$null_n <- 19; cfg$null_nsim <- 199
  null_max <- null_max_scores(r, cfg)
  expect_length(null_max, 19)
  expect_equal(null_pvalues(r$lines$score[1], null_max), 1 / 20)
})

test_that("merged lines carry side_gap, and score = side gap x log(length)", {
  expect_true("side_gap" %in% names(r$lines))
  expect_equal(r$lines$score, r$lines$side_gap * log(r$lines$length_m))
  e <- merge_cliff_lines(r$borders[0, ], r$units, 400, 150)
  expect_true("side_gap" %in% names(e))   # empty frame keeps the full schema
})

test_that("score is invariant to a monotonic relabelling of gap percentiles", {
  b2 <- r$borders
  b2$gap_pct <- stats::pnorm(3 * (b2$gap_pct - 0.5))
  l1 <- merge_cliff_lines(r$borders, r$units, 400, 150)
  l2 <- merge_cliff_lines(b2, r$units, 400, 150)
  expect_equal(l1$score, l2$score)
})

test_that("the planted absolute jump is recovered by side_gap", {
  zz <- standardise(s$irsad_2021)
  expected <- mean(zz[s$col <= 15]) - mean(zz[s$col > 15])
  expect_lt(abs(r$lines$side_gap[1] - expected) / expected, 0.2)
})

test_that("surrogate maps are scored with the same definition as the real map", {
  nb <- edges_to_nb(r$edges, nrow(r$units))
  Y <- sar_surrogate(nb, 0.9, 1, seed = 11)
  u <- r$units; u$.sim <- Y[, 1]
  rs <- find_cliffs(u, r$edges, ".sim", "score", nsim = 199, q = 0.05,
                    min_line_m = 400, seed = 2)
  if (nrow(rs$lines) > 0)
    expect_equal(rs$lines$score, rs$lines$side_gap * log(rs$lines$length_m))
  expect_equal(r$lines$score, r$lines$side_gap * log(r$lines$length_m))
})

test_that("reappears() matches lines within the distance", {
  expect_true(all(reappears(r$lines, r$lines, 1)))
  far <- sf::st_set_geometry(r$lines, sf::st_geometry(r$lines) + c(5000, 0))
  sf::st_crs(far) <- sf::st_crs(r$lines)
  expect_false(any(reappears(r$lines, far, 200)))
})
