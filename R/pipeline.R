# Orchestration. Each stage writes an .rds checkpoint under out/, so a failed or
# interrupted run resumes from the last completed stage.

cliffs_variables <- function() {
  data.frame(
    var   = c("irsad_2021", "hh_income_wk", "rent_wk", "median_age"),
    type  = c("score", "log", "log", "score"),
    label = c("Socio-economic advantage (SEIFA IRSAD 2021)",
              "Median household income ($/week)",
              "Median weekly rent ($)",
              "Median age (years)"),
    headline = c(TRUE, FALSE, FALSE, FALSE),
    stringsAsFactors = FALSE
  )
}

checkpoint <- function(name, paths, expr, refresh = FALSE) {
  f <- file.path(paths$out, paste0(name, ".rds"))
  if (!refresh && file.exists(f)) {
    log_step("checkpoint hit: ", name)
    return(readRDS(f))
  }
  val <- expr  # lazy argument: evaluated only on a checkpoint miss
  ensure_dir(paths$out)
  saveRDS(val, f)
  val
}

# Side-by-side profile of each cliff line on every variable: the median value of
# the high-side and low-side SA1s that touch the line (headline borders).
profile_lines <- function(res, sa1_tab, variables) {
  b <- res$borders
  if (is.null(b) || nrow(b) == 0) return(data.frame())
  codes <- res$units$sa1_code
  rows <- lapply(split(seq_len(nrow(b)), b$line_id), function(idx) {
    hi <- unique(codes[b$hi_unit[idx]]); lo <- unique(codes[b$lo_unit[idx]])
    vals <- lapply(variables$var, function(v) {
      x <- sa1_tab[[v]]; names(x) <- sa1_tab$sa1_code
      c(stats::median(x[hi], na.rm = TRUE), stats::median(x[lo], na.rm = TRUE))
    })
    out <- data.frame(line_id = b$line_id[idx[1]], n_hi = length(hi), n_lo = length(lo),
                      pop_hi = sum(sa1_tab$pop[match(hi, sa1_tab$sa1_code)], na.rm = TRUE),
                      pop_lo = sum(sa1_tab$pop[match(lo, sa1_tab$sa1_code)], na.rm = TRUE))
    for (k in seq_along(variables$var)) {
      out[[paste0(variables$var[k], "_hi")]] <- vals[[k]][1]
      out[[paste0(variables$var[k], "_lo")]] <- vals[[k]][2]
    }
    out
  })
  do.call(rbind, rows)
}

run_pipeline <- function(stages = "all", cfg = cliffs_config(), paths = cliffs_paths(),
                         online = TRUE, force = character()) {
  want <- function(s) "all" %in% stages || s %in% stages
  vars <- cliffs_variables()
  head_var <- vars[vars$headline, ]
  set.seed(cfg$seed)
  timings <- list()
  tick <- function(name, t) timings[[name]] <<- round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1)

  # ---- data -------------------------------------------------------------------
  sa1_path <- file.path(paths$out, "sa1.gpkg")
  if (want("data") || !file.exists(sa1_path)) {
    t <- Sys.time(); build_sa1(cfg, cliffs_sources(), paths); tick("data", t)
  }
  sa1 <- sf::st_read(sa1_path, quiet = TRUE)
  sa1$change_flag <- as.character(sa1$change_flag)

  # ---- universe + edges (built once at the loosest grid settings) ----------------
  t <- Sys.time()
  base <- checkpoint("base_graph", paths, refresh = "edges" %in% force, {
    u <- filter_units(sa1, min(cfg$grid$pop_floor), cfg$min_residential)
    log_step(sprintf("universe: %d SA1s (pop >= %d, residential >= %.0f%%)",
                     nrow(u), min(cfg$grid$pop_floor), 100 * cfg$min_residential))
    eg <- build_edges(u, min(cfg$grid$min_border_m))
    list(units = u, edges = eg$edges)
  })
  tick("edges", t)
  main <- subset_graph(base$units, base$edges[base$edges$border_m >= cfg$min_border_m, ],
                       base$units$pop >= cfg$pop_floor)
  log_step(sprintf("analysis graph: %d SA1s, %d edges, %d islands",
                   nrow(main$units), nrow(main$edges), n_islands(main$nb)))

  # ---- cliffs ---------------------------------------------------------------------
  t <- Sys.time()
  res <- checkpoint("cliffs_headline", paths, refresh = "cliffs" %in% force,
    find_cliffs(main$units, main$edges, head_var$var, head_var$type, nsim = cfg$lisa_nsim,
                q = cfg$fdr_q, min_line_m = cfg$min_line_m,
                     edge_pct = cfg$edge_pct, lisa_order = cfg$lisa_order, line_gap_m = cfg$line_gap_m, seed = cfg$seed))
  tick("cliffs", t)
  log_step(sprintf("headline: Moran's I = %.3f, %d cliff borders, %d cliff lines >= %d m",
                   res$moran_I, nrow(res$borders), nrow(res$lines), cfg$min_line_m))
  if (nrow(res$lines) == 0) {
    log_step("no cliff lines found at these settings; see report for diagnostics")
  }
  top <- utils::head(res$lines, cfg$top_n)

  # ---- streets ----------------------------------------------------------------------
  if (want("streets") && online && nrow(top) > 0) {
    t <- Sys.time()
    top <- checkpoint("streets", paths, refresh = "streets" %in% force,
                      classify_lines(top, cfg, paths$osm_cache))
    tick("streets", t)
  }

  # ---- checks -----------------------------------------------------------------------
  if (want("checks") && nrow(top) > 0) {
    t <- Sys.time()
    chk <- checkpoint("checks", paths, refresh = "checks" %in% force, {
      null_max <- null_max_scores(res, cfg)
      sens <- check_sensitivity(base$units, base$edges, top, head_var$var, head_var$type, cfg)
      list(
        null_max = null_max,
        p_null = null_pvalues(top$score, null_max),
        in_2016 = check_time(main$units, main$edges, top, cfg),
        stability = sens$stability,
        stability_detail = sens$detail
      )
    })
    top$p_null <- chk$p_null
    top$in_2016 <- chk$in_2016
    top$stability <- chk$stability
    top$passes_all <- top$p_null <= 0.05 & top$in_2016 & top$stability >= 0.8
    tick("checks", t)
  }

  # ---- profile + outputs --------------------------------------------------------------
  prof <- profile_lines(res, sf::st_drop_geometry(sa1), vars)
  top_tab <- sf::st_drop_geometry(top)
  cen <- sf::st_coordinates(sf::st_centroid(sf::st_transform(sf::st_geometry(top), 4326)))
  top_tab$lon <- cen[, 1]; top_tab$lat <- cen[, 2]
  if (nrow(prof)) top_tab <- merge(top_tab, prof, by = "line_id", all.x = TRUE)
  top_tab <- top_tab[order(-top_tab$score), ]

  readr::write_csv(top_tab, file.path(paths$out, "cliffs_top.csv"))
  sf::st_write(top, file.path(paths$out, "cliffs.gpkg"), layer = "lines", delete_dsn = TRUE, quiet = TRUE)
  lab <- res$units; lab$label <- res$labels$label; lab$z <- res$labels$z; lab$p_fdr <- res$labels$p_fdr
  sf::st_write(lab[, c("sa1_code", "label", "z", "p_fdr")], file.path(paths$out, "cliffs.gpkg"),
               layer = "lisa", append = TRUE, quiet = TRUE)

  # ---- maps -------------------------------------------------------------------------
  if (want("maps") && nrow(top) > 0) {
    for (id in utils::head(top_tab$line_id, 3)) {
      row <- top_tab[top_tab$line_id == id, ]
      nm <- if (!is.null(row$border_name) && !is.na(row$border_name)) row$border_name else "this border"
      write_cliff_map(res, id, file.path(paths$out, "maps", sprintf("cliff_%02d.html", id)),
                      title = sprintf("Cross %s and Sydney changes", nm),
                      subtitle = sprintf("%s vs %s", row$hi_area, row$lo_area),
                      value_label = head_var$label)
    }
  }

  meta <- list(
    run_at = format(Sys.time(), tz = "Australia/Sydney", usetz = TRUE),
    config = cfg[setdiff(names(cfg), c("grid"))], grid = cfg$grid,
    n_sa1_total = nrow(sa1), n_units = res$n_units, n_edges = nrow(main$edges),
    islands = n_islands(main$nb), moran_I = res$moran_I,
    n_cliff_borders = nrow(res$borders), n_cliff_lines = nrow(res$lines),
    label_counts = as.list(table(res$labels$label)),
    timings_s = timings, r_version = R.version.string,
    packages = vapply(c("sf", "spdep", "Matrix", "httr2"), function(p) as.character(utils::packageVersion(p)), "")
  )
  jsonlite::write_json(meta, file.path(paths$out, "run_meta.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  log_step("done. Top cliffs: out/cliffs_top.csv")
  invisible(list(res = res, top = top_tab, meta = meta))
}
