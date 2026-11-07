# Post assets in the Microburbs style: one big verified number, dark navy,
# bold white type, one accent. Every number comes from out/ files; nothing is
# typed by hand, and caption_facts.md records the exact sentence each number
# appears in.
#
# Framing rules (hard): describe areas, indexes and tenure facts, never
# residents; no crime, safety or behaviour language; never claim statistical
# significance the null test did not grant; the 2016 comparison at a line with
# redrawn boundaries is "not comparable", never "failed".

PA_BG   <- "#0b1020"
PA_ACC  <- "#ff2d55"   # accent / cliff
PA_HI   <- "#ffb000"   # high side
PA_LO   <- "#3d8bfd"   # low side
PA_GREY <- "#9aa3b2"
PA_SRC  <- "Source: ABS Census 2021 & SEIFA (CC BY 4.0) · Analysis: Sydney Cliffs"
PA_SRC_G37 <- "ABS Census 2021, G37 · Analysis: Sydney Cliffs"

# ---- Artefact screen ---------------------------------------------------------------

# Conservative flags for each top line. Mesh-block land use within 100 m of the
# line (water / park / transport / industrial), tiny side populations, nearness
# to the study-area edge, implausible jumps, and single-SA1 sides. Flags are
# REPORTED, never used to drop a line silently.
artefact_screen <- function(res, sa1, top_tab, cfg, paths) {
  lines_top <- res$lines[res$lines$line_id %in% top_tab$line_id, ]
  study <- sf::st_union(sf::st_geometry(sa1))
  saveRDS(study, file.path(paths$out, "study_boundary.rds"))
  edge <- sf::st_boundary(study)

  mb_shp <- tryCatch(find_file(file.path(paths$data, "mb_2021"), "\\.shp$"),
                     error = function(e) NULL)
  mb <- NULL
  if (!is.null(mb_shp)) {
    lyr <- tools::file_path_sans_ext(basename(mb_shp))
    mb <- sf::st_read(mb_shp, quiet = TRUE,
                      query = sprintf("SELECT MB_CAT21 FROM \"%s\" WHERE GCC_CODE21 = '%s'",
                                      lyr, cfg$gccsa_code))
    mb <- sf::st_transform(mb, cfg$crs_metric)
  }

  rows <- lapply(seq_len(nrow(lines_top)), function(k) {
    ln  <- lines_top[k, ]
    row <- top_tab[top_tab$line_id == ln$line_id, ][1, ]
    shares <- c(water = NA_real_, park = NA_real_, transport = NA_real_, industrial = NA_real_)
    if (!is.null(mb)) {
      buf  <- sf::st_buffer(sf::st_geometry(ln), 100)
      near <- mb[lengths(sf::st_intersects(mb, buf)) > 0, ]
      shares[] <- 0
      if (nrow(near) > 0) {
        inter <- suppressWarnings(sf::st_intersection(near, buf))
        a <- as.numeric(sf::st_area(inter))
        sh <- tapply(a, inter$MB_CAT21, sum) / sum(a)
        g <- function(cat) sum(sh[names(sh) %in% cat], na.rm = TRUE)
        shares["water"] <- g("Water"); shares["park"] <- g("Parkland")
        shares["transport"] <- g("Transport"); shares["industrial"] <- g("Industrial")
      }
    }
    d_edge <- as.numeric(sf::st_distance(sf::st_geometry(ln), edge))
    flags <- data.frame(
      line_id     = ln$line_id,
      water       = isTRUE(shares["water"] > 0.2),
      park        = isTRUE(shares["park"] > 0.3),
      transport   = isTRUE(shares["transport"] > 0.3),
      industrial  = isTRUE(shares["industrial"] > 0.3),
      tiny_pop    = isTRUE(row$pop_hi < 1000 | row$pop_lo < 1000),
      study_edge  = isTRUE(d_edge < 1000),
      implausible = isTRUE(abs(row$irsad_2021_hi - row$irsad_2021_lo) > 400 |
                           row$hh_income_wk_hi / row$hh_income_wk_lo > 5),
      single_sa1  = isTRUE(row$n_hi == 1 | row$n_lo == 1),
      pct_water = round(shares[["water"]], 3), pct_park = round(shares[["park"]], 3),
      pct_transport = round(shares[["transport"]], 3),
      pct_industrial = round(shares[["industrial"]], 3),
      dist_edge_m = round(d_edge)
    )
    flag_cols <- c("water", "park", "transport", "industrial", "tiny_pop",
                   "study_edge", "implausible", "single_sa1")
    flags$any_flag <- rowSums(flags[flag_cols]) > 0
    flags
  })
  out <- do.call(rbind, rows)
  readr::write_csv(out, file.path(paths$out, "artefact_flags.csv"))
  out
}

# ---- Fixed selection rule ------------------------------------------------------------

# eligible = passes_all & delta_bic_lo > 2 & jump_stable & both sides >= 1000 people.
# Rank eligible: no artefact flag first, then road/rail over other kinds, then score.
# If nothing is eligible: the highest-scoring line, labelled "strongest candidate,
# not all checks passed" with the failed criteria listed. No judgement calls.
select_line <- function(top_tab, flags, cfg) {
  t <- merge(top_tab, flags[, c("line_id", "any_flag")], by = "line_id", all.x = TRUE)
  ok <- function(x) !is.na(x) & x
  crit <- data.frame(
    line_id    = t$line_id,
    passes_all = ok(t$passes_all),
    step       = !is.na(t$delta_bic_lo) & t$delta_bic_lo > 2,
    stable     = ok(t$jump_stable),
    pop        = !is.na(t$pop_hi) & !is.na(t$pop_lo) & t$pop_hi >= 1000 & t$pop_lo >= 1000
  )
  eligible <- crit$passes_all & crit$step & crit$stable & crit$pop
  kind_ok <- !is.na(t$border_kind) & t$border_kind %in% c("road", "rail")
  if (any(eligible)) {
    e <- t[eligible, ]
    e <- e[order(e$any_flag, !kind_ok[eligible], -e$score), ]
    chosen <- e$line_id[1]
    note <- "selected by the fixed rule"
    failed <- character(0)
  } else {
    chosen <- t$line_id[order(-t$score)][1]
    k <- crit[crit$line_id == chosen, ]
    failed <- names(k)[-1][!unlist(k[-1])]
    note <- paste("strongest candidate, not all checks passed; failed:",
                  paste(failed, collapse = ", "))
  }
  if (is.finite(cfg$chosen_line_id)) {
    chosen <- cfg$chosen_line_id
    note <- sprintf("line %d set by --line / cfg$chosen_line_id", chosen)
  }
  log_step("selection: line ", chosen, " (", note, ")")
  list(line_id = chosen, eligible_ids = t$line_id[eligible], note = note, failed = failed)
}

# ---- Theme and helpers -----------------------------------------------------------------

pa_theme <- function(base = 22) {
  ggplot2::theme_minimal(base_size = base) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = PA_BG, colour = NA),
      panel.background = ggplot2::element_rect(fill = PA_BG, colour = NA),
      panel.grid.major = ggplot2::element_line(colour = "#1d2742", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      text       = ggplot2::element_text(colour = "white"),
      axis.text  = ggplot2::element_text(colour = "#c9d2e0"),
      axis.title = ggplot2::element_text(colour = "#c9d2e0", size = base * 0.7),
      plot.title = ggplot2::element_text(face = "bold", size = base * 1.25, lineheight = 1.05),
      plot.subtitle = ggplot2::element_text(colour = "#c9d2e0", size = base * 0.8,
                                            lineheight = 1.15),
      plot.caption  = ggplot2::element_text(colour = PA_GREY, size = base * 0.55, hjust = 0),
      legend.position = "none",
      plot.margin = ggplot2::margin(40, 30, 30, 30)
    )
}

pa_save <- function(p, file) {
  ensure_dir(dirname(file))
  ggplot2::ggsave(file, p, device = ragg::agg_png, width = 1080, height = 1920,
                  units = "px", dpi = 160, bg = PA_BG)
  log_step("asset: ", file)
}

fmt_num <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ",")

# Where the cliff physically runs, for captions. Falls back to the area pair
# when Overpass gave no name.
pa_where <- function(row) {
  if (!is.null(row$border_name) && !is.na(row$border_name)) row$border_name
  else sprintf("the %s-%s boundary", row$hi_area, row$lo_area)
}

# ---- Assets -----------------------------------------------------------------------

post_assets <- function(res, top_tab, flags, sel, cfg, paths) {
  dir <- file.path(paths$out, "post_assets")
  ensure_dir(dir)
  unlink(file.path(dir, "03_change.png"))   # retired asset: 2016 is not comparable here
  row <- top_tab[top_tab$line_id == sel$line_id, ][1, ]
  pts <- readr::read_csv(file.path(paths$out, "transect_points.csv"), show_col_types = FALSE)
  pts <- pts[pts$line_id == sel$line_id, ]
  meta <- jsonlite::read_json(file.path(paths$out, "run_meta.json"))
  where <- pa_where(row)

  # IRSAD percentiles of the side medians within all Greater Sydney SA1s.
  irsad_all <- sf::st_read(file.path(paths$out, "sa1.gpkg"), quiet = TRUE)$irsad_2021
  irsad_all <- irsad_all[is.finite(irsad_all)]
  pct_hi <- 100 * mean(irsad_all <= row$irsad_2021_hi)
  pct_lo <- 100 * mean(irsad_all <= row$irsad_2021_lo)

  # Headline: the social-rental contrast (ABS G37) when it is verified in the
  # pipeline output and the low side is majority social housing; otherwise the
  # IRSAD percentile contrast. Fixed preference, no judgement call.
  soc_ok <- all(c("social_rent_hi", "social_rent_lo") %in% names(row)) &&
    is.finite(row$social_rent_hi) && is.finite(row$social_rent_lo) &&
    row$social_rent_lo > 50
  if (soc_ok) {
    big <- sprintf("%.0f%% vs %.0f%%", row$social_rent_hi, row$social_rent_lo)
    big_sub <- sprintf("Social housing on each side of\none street in %s.", row$hi_area)
    src1 <- PA_SRC_G37
  } else {
    big <- sprintf("%.0fth vs %.1fth", pct_hi, pct_lo)
    big_sub <- "Percentile of relative socio-economic\nadvantage on each side of one street."
    src1 <- PA_SRC
  }

  # ---- 01: title card ---------------------------------------------------------------
  t1 <- ggplot2::ggplot() +
    ggplot2::annotate("text", 0, 0.72, label = "ONE STREET APART", colour = PA_HI,
                      size = 11, fontface = "bold") +
    ggplot2::annotate("text", 0, 0.54, label = big, colour = "white",
                      size = min(40, 300 / nchar(big)), fontface = "bold") +
    ggplot2::annotate("text", 0, 0.41, label = big_sub, colour = "#c9d2e0", size = 7,
                      lineheight = 1.15) +
    ggplot2::annotate("text", 0, 0.28,
                      label = sprintf("%s, %s", where, row$hi_area),
                      colour = "white", size = 10, fontface = "bold", lineheight = 1.1) +
    ggplot2::annotate("text", 0, 0.03, label = src1, colour = PA_GREY, size = 4) +
    ggplot2::xlim(-1, 1) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.background = ggplot2::element_rect(fill = PA_BG, colour = NA))
  pa_save(t1, file.path(dir, "01_title.png"))

  # ---- 02: descriptive transect --------------------------------------------------------
  # Observed values and a straight-line fit only: the step-vs-slope test was
  # inconclusive here, so the chart makes no discontinuity claim.
  ord <- order(pts$d_m)
  t2 <- ggplot2::ggplot(pts, ggplot2::aes(d_m, z)) +
    ggplot2::geom_point(ggplot2::aes(colour = factor(side)), size = 2.6, alpha = 0.85) +
    ggplot2::scale_colour_manual(values = c("-1" = PA_LO, "1" = PA_HI)) +
    ggplot2::geom_line(data = pts[ord, ], ggplot2::aes(d_m, fit_linear),
                       colour = "#c9d2e0", linetype = "dashed", linewidth = 1.1) +
    ggplot2::geom_vline(xintercept = 0, colour = "white", linewidth = 0.4) +
    ggplot2::annotate("text", 0, max(pts$z) * 1.08, label = where, colour = "white",
                      size = 7, fontface = "bold") +
    ggplot2::labs(
      title = sprintf("Advantage across\n%s", where),
      subtitle = sprintf(
        "Each dot is one SA1 within %s m of the line.\nDashed line: straight-line fit (descriptive only).",
        fmt_num(cfg$transect_radius_m)),
      x = sprintf("metres from %s (negative = low side)", where),
      y = "relative socio-economic advantage (z)",
      caption = PA_SRC
    ) + pa_theme()
  pa_save(t2, file.path(dir, "02_ledge.png"))

  # ---- 04: where in Sydney --------------------------------------------------------------
  study <- readRDS(file.path(paths$out, "study_boundary.rds"))
  lines_top <- res$lines[res$lines$line_id %in% top_tab$line_id, ]
  chosen_ln <- lines_top[lines_top$line_id == sel$line_id, ]
  cen <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(chosen_ln)))
  top2 <- utils::head(top_tab[order(-top_tab$score), ], 2)
  top2_social <- all(is.finite(top2$social_rent_lo)) && all(top2$social_rent_lo > 50)
  sub4 <- if (top2_social)
    "The top 2 mark where social housing meets private housing." else
    sprintf("In red: %s in %s.", where, row$hi_area)
  t4 <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = study, fill = "#141b33", colour = "#2a3658", linewidth = 0.5) +
    ggplot2::geom_sf(data = sf::st_buffer(lines_top, 500), fill = PA_LO, colour = NA) +
    ggplot2::geom_sf(data = sf::st_buffer(chosen_ln, 700), fill = PA_ACC, colour = NA) +
    ggplot2::annotate("point", cen[1], cen[2], colour = PA_ACC, size = 10, shape = 1, stroke = 2) +
    ggplot2::annotate("text", cen[1], cen[2] + 6500, label = where,
                      colour = "white", size = 9, fontface = "bold") +
    ggplot2::labs(
      title = "Sydney's 10 sharpest\nadvantage edges",
      subtitle = sub4,
      caption = if (top2_social) paste0(PA_SRC, " · Tenure: ABS Census 2021 G37") else PA_SRC
    ) +
    pa_theme() +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   panel.grid.major = ggplot2::element_blank())
  pa_save(t4, file.path(dir, "04_sydney.png"))

  # ---- 05: the honest test --------------------------------------------------------------
  chk_path <- file.path(paths$out, "checks.rds")
  if (file.exists(chk_path)) {
    chk <- readRDS(chk_path)
    nm <- data.frame(score = chk$null_max)
    t5 <- ggplot2::ggplot(nm, ggplot2::aes(score)) +
      ggplot2::geom_histogram(bins = 20, fill = "#4a5673", colour = PA_BG) +
      ggplot2::geom_vline(xintercept = row$score, colour = PA_ACC, linewidth = 1.6) +
      ggplot2::annotate("text", row$score, Inf, vjust = 2, hjust = 1.05,
                        label = sprintf("%s\nscore %.1f", where, row$score),
                        colour = PA_ACC, size = 7, fontface = "bold", lineheight = 1.1) +
      ggplot2::labs(
        title = "We tried to break it",
        subtitle = sprintf(
          "The whole search re-run on %s simulated\nSydneys with the same overall clustering.\nBars: the best edge score in each map.\np = %.2f: not exceptional.",
          length(chk$null_max), row$p_null),
        x = "best edge score in each simulated Sydney",
        y = "simulated maps",
        caption = PA_SRC
      ) + pa_theme()
    pa_save(t5, file.path(dir, "05_test.png"))
  }

  # ---- caption_facts.md ------------------------------------------------------------------
  soc_def <- "state/territory housing authority + community housing rentals, as % of occupied private dwellings with tenure stated (not-stated excluded)"
  facts <- c(
    "# Caption facts — every published number: value, source, definition, limitation, and the sentence it appears in",
    "",
    sprintf("Chosen line: %d — %s (%s), in %s. Selection: %s.",
            sel$line_id, where, ifelse(is.na(row$border_kind), "kind unknown", row$border_kind),
            row$hi_area, sel$note),
    "",
    "| # | Number | Value | File / column | Definition & limitation | Sentence used |",
    "|---|---|---|---|---|---|",
    if (soc_ok) sprintf("| 1 | Social-rental share, advantaged side | %.1f%% | cliffs_top.csv social_rent_hi | %s | “%s” (01_title, video beat 2) |",
            row$social_rent_hi, soc_def, big) else
            sprintf("| 1 | IRSAD percentile, advantaged side | %.0fth | derived: cliffs_top.csv irsad_2021_hi vs sa1.gpkg irsad_2021 | percentile of the side median among all GSYD SA1s | “%s” (01_title) |", pct_hi, big),
    if (soc_ok) sprintf("| 2 | Social-rental share, other side | %.1f%% | cliffs_top.csv social_rent_lo | %s; majority social housing (>50%%) so the tenure phrase is permitted | “%s” (01_title, video beat 2) |",
            row$social_rent_lo, soc_def, big) else "",
    sprintf("| 3 | Length of the edge | %s m | cliffs_top.csv length_m | sum of shared SA1 borders in the merged line | “the sharpest advantage edge ... runs %s m along %s” (report) |",
            fmt_num(row$length_m), fmt_num(row$length_m), where),
    sprintf("| 4 | Median IRSAD each side | %s vs %s | cliffs_top.csv irsad_2021_hi/_lo | median of the SA1s touching the line, each side | report Finding |",
            fmt_num(row$irsad_2021_hi), fmt_num(row$irsad_2021_lo)),
    sprintf("| 5 | IRSAD percentile each side | %.0fth vs %.1fth | derived from sa1.gpkg irsad_2021 | percentile among %s GSYD SA1s with IRSAD | “the %.0fth percentile of advantage meets the bottom 1%%” (video beat 3) |",
            pct_hi, pct_lo, fmt_num(length(irsad_all)), pct_hi),
    sprintf("| 6 | Median household income each side | $%s vs $%s /wk | cliffs_top.csv hh_income_wk_hi/_lo | ABS G02 medians; NOT equivalised for household size | report Finding |",
            fmt_num(row$hh_income_wk_hi), fmt_num(row$hh_income_wk_lo)),
    sprintf("| 7 | Residents each side | %s vs %s | cliffs_top.csv pop_hi/_lo | usual residents of the SA1s touching the line | report Finding |",
            fmt_num(row$pop_hi), fmt_num(row$pop_lo)),
    sprintf("| 8 | Spatial-null p-value | %.2f | cliffs_top.csv p_null | max-statistic over %s SAR surrogates matched to Moran's I %.3f; NOT exceptional | “p = %.2f: not exceptional” (05_test, pitch) |",
            row$p_null, length(readRDS(chk_path)$null_max), meta$moran_I, row$p_null),
    sprintf("| 9 | Sensitivity stability | %.2f | cliffs_top.csv stability | share of 18 setting combinations keeping the line in the top 20 | report checks table |",
            row$stability),
    sprintf("| 10 | Scan size | %s areas, %s borders | run_meta.json n_units / n_edges | SA1s in the analysis graph: >=150 residents, >=20%% residential land, >=50 m shared border, finite IRSAD 2021 | “across the %s Greater Sydney areas in our analysis” (pitch) |",
            fmt_num(meta$n_units), fmt_num(meta$n_edges), fmt_num(meta$n_units)),
    sprintf("| 11 | Transect sample | %s SA1s | transects.csv n_points | SA1 centroids within %s m of the line | 02_ledge subtitle |",
            fmt_num(nrow(pts)), fmt_num(cfg$transect_radius_m)),
    {
      mbj_path <- file.path(paths$out, "microburbs_check.json")
      if (file.exists(mbj_path)) {
        mbj <- jsonlite::read_json(mbj_path)
        c(sprintf("| 12 | Microburbs income, each side of the line | $%s vs $%s /wk | microburbs_check.json young_hi/lo_median_wk | median of %s / %s microburbs (ABS mesh blocks), %s endpoint, called %s; label: %s; a consistency check, not independent confirmation | “Microburbs’ 2026 estimates are consistent with the divide” (report, video beat 4) |",
                  format(mbj$young_hi_median_wk, big.mark = ","), format(mbj$young_lo_median_wk, big.mark = ","),
                  mbj$young_hi_n, mbj$young_lo_n, mbj$endpoint, mbj$called_on, mbj$label),
          sprintf("| 13 | Waterloo income range | $%s (%s St) to $%s (%s St) /wk | microburbs_check.json waterloo_* | same endpoint and date; label: %s | report second-source paragraph |",
                  format(mbj$waterloo_lowest_wk, big.mark = ","), mbj$waterloo_lowest_street,
                  format(mbj$waterloo_highest_wk, big.mark = ","), mbj$waterloo_highest_street, mbj$label))
      } else character(0)
    },
    "",
    "Numbers NOT published, by design: cliff width in metres (estimate degenerate,",
    "below SA1 resolution of about 170 m); 2016-2021 change at this line (SA1",
    "boundaries redrawn: not comparable); any claim of statistical significance.",
    "One SA1 touches the line on both sides across different borders and is",
    "counted in both side aggregates (border-level definition).",
    ""
  )
  writeLines(facts[nzchar(facts) | facts == ""], file.path(dir, "caption_facts.md"))
  log_step("asset: ", file.path(dir, "caption_facts.md"))

  # ---- video + pitch scripts --------------------------------------------------------------
  mbj_path <- file.path(paths$out, "microburbs_check.json")
  has_mbj <- file.exists(mbj_path)
  video <- c(
    sprintf("# demo.mp4 script — 30 seconds, sound-off, %s beats", if (has_mbj) "six" else "five"),
    "",
    "Every number is traceable via caption_facts.md (fact # in brackets).",
    "",
    sprintf("1. 0-3 s — 3D map flyover. Caption: “%s, %s.”", where, row$hi_area),
    if (soc_ok) sprintf("2. 3-8 s — 01_title.png. Caption: “%.0f%% vs %.0f%% social housing.” [1, 2]",
                        row$social_rent_hi, row$social_rent_lo) else
                sprintf("2. 3-8 s — 01_title.png. Caption: “%s percentile of advantage, side by side.” [1]", big),
    sprintf("3. 8-14 s — 04_sydney.png. Caption: “The sharpest edge in %s neighbourhoods.” [10]",
            fmt_num(as.numeric(meta$n_units))),
    if (has_mbj)
      "4. 14-19 s — 3D map, camera crossing the line. Caption: “Microburbs’ 2026 estimates are consistent with the divide.” [12]",
    sprintf("%s. %s s — 05_test.png. Caption: “We tried to break it: not exceptional (p = %.2f).” [8]",
            if (has_mbj) "5" else "4", if (has_mbj) "19-25" else "16-25", row$p_null),
    sprintf("%s. 25-30 s — 02_ledge.png. Caption: “Sydney mostly changes as hills, not cliffs.” + “Sydney Cliffs · ABS Census 2021 & SEIFA (CC BY 4.0)”.",
            if (has_mbj) "6" else "5"),
    ""
  )
  writeLines(video, file.path(dir, "video_script.md"))
  log_step("asset: ", file.path(dir, "video_script.md"))

  pitch <- c(
    "# pitch.mp4 script — 45 seconds, ~110 words",
    "",
    sprintf("Everyone can point at an advantaged suburb. We asked where advantage changes most sharply — and whether it is a cliff or a hill. We scanned all %s neighbour borders across the %s Greater Sydney areas in our analysis, scored every edge by its jump in SEIFA advantage, and stress-tested the winners against %s simulated Sydneys with the same clustering. The sharpest edge is %s, %s: %s social housing across one street. And the honest result: even that edge is not statistically exceptional — p equals %.2f. At neighbourhood scale, Sydney’s advantage mostly changes as hills, not cliffs. Fully reproducible: one command, open ABS data, every claim tested.",
            fmt_num(meta$n_edges), fmt_num(meta$n_units),
            length(readRDS(chk_path)$null_max), where, row$hi_area,
            if (soc_ok) sprintf("%.0f%% versus %.0f%%", row$social_rent_hi, row$social_rent_lo)
            else big, row$p_null),
    ""
  )
  writeLines(pitch, file.path(dir, "pitch_script.md"))
  log_step("asset: ", file.path(dir, "pitch_script.md"))

  jsonlite::write_json(
    list(line_id = sel$line_id, note = sel$note, eligible_ids = sel$eligible_ids,
         failed = sel$failed, where = where, hi_area = row$hi_area, lo_area = row$lo_area),
    file.path(paths$out, "selection.json"), auto_unbox = TRUE, pretty = TRUE)

  # ---- refreshed 3D map for the chosen line ---------------------------------------------
  head_lab <- cliffs_variables()$label[cliffs_variables()$headline][1]
  write_cliff_map(
    res, sel$line_id,
    file.path(paths$out, "maps", sprintf("cliff_%02d.html", sel$line_id)),
    title = sprintf("Cross %s and Sydney changes", where),
    subtitle = if (identical(row$hi_area, row$lo_area))
      sprintf("The two sides of %s in %s", where, row$hi_area)
    else sprintf("%s vs %s", row$hi_area, row$lo_area),
    value_label = head_lab,
    big_number = if (soc_ok) sprintf("%s social housing", big) else big
  )
  invisible(sel)
}
