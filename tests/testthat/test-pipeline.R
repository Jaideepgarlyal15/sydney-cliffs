# End to end on synthetic data: checkpoints, checks, outputs and the map page.

test_that("the full pipeline runs offline on synthetic data", {
  tmp <- withr_tempdir()
  s <- make_synthetic_sa1()
  ensure_dir(file.path(tmp, "out"))
  sf::st_write(s[, setdiff(names(s), c("col", "row"))], file.path(tmp, "out", "sa1.gpkg"), quiet = TRUE)

  cfg <- cliffs_config()
  cfg$lisa_nsim <- 499; cfg$null_n <- 19; cfg$null_nsim <- 199; cfg$grid_nsim <- 199
  cfg$min_residential <- 0.5
  paths <- cliffs_paths(tmp)
  out <- suppressMessages(run_pipeline(stages = c("cliffs", "checks", "maps"), cfg = cfg,
                                       paths = paths, online = FALSE))

  top <- readr::read_csv(file.path(tmp, "out", "cliffs_top.csv"), show_col_types = FALSE)
  expect_gte(nrow(top), 1)
  expect_true(all(c("line_id", "length_m", "score", "p_null", "in_2016", "stability",
                    "passes_all", "irsad_2021_hi", "irsad_2021_lo", "lon", "lat") %in% names(top)))
  expect_true(top$passes_all[1])
  expect_gt(top$irsad_2021_hi[1], top$irsad_2021_lo[1])

  meta <- jsonlite::read_json(file.path(tmp, "out", "run_meta.json"))
  expect_equal(meta$n_units, 900)
  expect_true(file.exists(file.path(tmp, "out", "cliffs.gpkg")))
  expect_setequal(sf::st_layers(file.path(tmp, "out", "cliffs.gpkg"))$name, c("lines", "lisa"))

  html <- list.files(file.path(tmp, "out", "maps"), full.names = TRUE)
  expect_gte(length(html), 1)
  page <- paste(readLines(html[1]), collapse = "\n")
  expect_false(grepl("__[A-Z_]+__", page))       # every placeholder substituted
  expect_true(grepl("FeatureCollection", page))  # data embedded

  # Second run hits checkpoints and gives the same answer.
  out2 <- suppressMessages(run_pipeline(stages = c("cliffs", "checks"), cfg = cfg,
                                        paths = paths, online = FALSE))
  expect_equal(out$top$score, out2$top$score)
})
