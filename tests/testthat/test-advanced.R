# Advanced modules on synthetic data with known answers: the planted step must
# look like a step (not a slope), its jump and width must be recovered, a pure
# gradient must prefer the linear model, and the 2016 gap-change must find a
# planted widening and nothing in identical years.

s  <- make_synthetic_sa1()
eg <- build_edges(s, 50)
r  <- find_cliffs(s, eg$edges, "irsad_2021", "score", nsim = 999, q = 0.05,
                  min_line_m = 400, seed = 1)
tf <- transect_fit(r, r$lines$line_id[1], radius_m = 1500,
                   bandwidths = c(300, 500, 800), boot_n = 99, seed = 7)

test_that("transect: signed distance sides agree", {
  expect_true(all(tf$points$side == tf$points$side_geom))
  expect_true(all(tf$points$z[tf$points$d_m > 300] |> mean() >
                  tf$points$z[tf$points$d_m < -300] |> mean()))
})

test_that("transect: synthetic step prefers the logistic model", {
  expect_gt(tf$summary$delta_bic, 10)
  expect_gt(tf$summary$p_step_boot, 0.9)
})

test_that("transect: synthetic step width is narrow", {
  expect_lt(tf$summary$width_m, 2 * 150)   # under two cell widths
})

test_that("transect: planted jump recovered within 15%", {
  true_jump_z <- 300 / sd(tf$points$raw)   # 3 SD * 100 IRSAD points, locally standardised
  expect_lt(abs(tf$summary$jump_500 - true_jump_z) / true_jump_z, 0.15)
  expect_true(tf$summary$jump_stable)
})

test_that("transect: synthetic gradient prefers linear", {
  sg <- make_synthetic_sa1(pattern = "gradient", outlier = FALSE, seed = 2)
  cen <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_geometry(sg))))
  mid <- attr(sg, "true_cliff_x")
  keep <- abs(cen[, 1] - mid) <= 1500
  d <- cen[keep, 1] - mid
  z <- standardise(sg$irsad_2021[keep])
  f <- fit_step_vs_slope(d, z)
  expect_lt(f$delta_bic, 2)
})

test_that("gap change: identical years give change 0", {
  r0 <- r
  r0$units$irsad_2016 <- r0$units$irsad_2021
  g <- gap_change(r0, boot_n = 99, seed = 3)
  expect_equal(g$gap_change, rep(0, nrow(g)), tolerance = 1e-10)
  expect_true(all(g$gap_change_lo <= 0 & g$gap_change_hi >= 0))
})

test_that("gap change: a planted widening is detected with CI above 0", {
  s2 <- make_synthetic_sa1()
  set.seed(42)
  # 2016 step is 0.9 (vs 3.0 in 2021) with the same noise: the relative gap widened.
  s2$irsad_2016 <- 1000 + 100 * (ifelse(s2$col <= 15, 0.45, -0.45) +
                                 stats::rnorm(nrow(s2), sd = 0.6))
  r2 <- find_cliffs(s2, build_edges(s2, 50)$edges, "irsad_2021", "score",
                    nsim = 999, q = 0.05, min_line_m = 400, seed = 1)
  g <- gap_change(r2, boot_n = 199, seed = 4)
  expect_gt(g$gap_change[1], 0)
  expect_gt(g$gap_change_lo[1], 0)
})

test_that("run_advanced writes both CSVs with the required columns", {
  tmp <- withr_tempdir()
  dir.create(file.path(tmp, "out"))
  cfg <- cliffs_config(); cfg$boot_n <- 49
  adv <- run_advanced(r, r$lines$line_id[1], cfg, list(out = file.path(tmp, "out")))
  need <- c("line_id", "n_points", "delta_bic", "delta_bic_lo", "delta_bic_hi",
            "p_step_boot", "width_m", "width_lo", "width_hi", "jump_300", "jump_500",
            "jump_800", "jump_500_lo", "jump_500_hi", "jump_stable",
            "gap_2016", "gap_2021", "gap_change", "gap_change_lo", "gap_change_hi")
  expect_true(all(need %in% names(adv)))
  tcsv <- readr::read_csv(file.path(tmp, "out", "transects.csv"), show_col_types = FALSE)
  pcsv <- readr::read_csv(file.path(tmp, "out", "transect_points.csv"), show_col_types = FALSE)
  expect_true(all(need %in% names(tcsv)))
  expect_true(all(c("line_id", "sa1_code", "d_m", "z", "side",
                    "fit_linear", "fit_logistic") %in% names(pcsv)))
  expect_equal(nrow(tcsv), 1)
  expect_gt(nrow(pcsv), 50)
})
