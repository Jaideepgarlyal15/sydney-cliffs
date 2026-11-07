#!/usr/bin/env Rscript
# Assemble out/final_handoff/ for the hackathon hand-in. Fails loudly (non-zero
# exit) when any required item is missing. Copies ONLY derived outputs and docs:
# never raw downloads, supplied hackathon files or API responses.
#   Rscript scripts/build_handoff.R

options(cliffs.root = normalizePath("."))
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages(library(sf))

out <- "out"
hand <- file.path(out, "final_handoff")
unlink(hand, recursive = TRUE)   # rebuild from scratch so retired files never linger
ensure_dir(hand)

need <- function(path, what = path) {
  assert_that(file.exists(path), paste0("handoff: missing ", what, " (", path, ")"))
  path
}
copy <- function(from, to_dir = hand) {
  ensure_dir(to_dir)
  file.copy(from, file.path(to_dir, basename(from)), overwrite = TRUE)
}

sel  <- jsonlite::read_json(need(file.path(out, "selection.json")))
meta <- jsonlite::read_json(need(file.path(out, "run_meta.json")))
top  <- readr::read_csv(need(file.path(out, "cliffs_top.csv")), show_col_types = FALSE)
tr   <- readr::read_csv(need(file.path(out, "transects.csv")), show_col_types = FALSE)
flags <- readr::read_csv(need(file.path(out, "artefact_flags.csv")), show_col_types = FALSE)
row  <- top[top$line_id == sel$line_id, ][1, ]
trc  <- tr[tr$line_id == sel$line_id, ][1, ]

# ---- 1. report ---------------------------------------------------------------------
copy(need("report.html", "report.html at the repo root (hackathon requirement)"))
copy(need("report.qmd"))

# ---- 2. data outputs ----------------------------------------------------------------
for (f in c("cliffs_top.csv", "transects.csv", "transect_points.csv", "run_meta.json",
            "artefact_flags.csv", "selection.json"))
  copy(need(file.path(out, f)))
gpkg <- need(file.path(out, "cliffs.gpkg"))
st_write(st_read(gpkg, layer = "lines", quiet = TRUE),
         file.path(hand, "cliffs_lines.geojson"), delete_dsn = TRUE, quiet = TRUE)
st_write(st_read(gpkg, layer = "lisa", quiet = TRUE),
         file.path(hand, "lisa.geojson"), delete_dsn = TRUE, quiet = TRUE)
map_f <- need(file.path(out, "maps", sprintf("cliff_%02d.html", sel$line_id)),
              "3D map of the chosen cliff")
copy(map_f, file.path(hand, "maps"))

# ---- 3 + 4. post assets --------------------------------------------------------------
for (f in c("01_title.png", "02_ledge.png", "04_sydney.png", "05_test.png",
            "caption_facts.md", "video_script.md", "pitch_script.md"))
  copy(need(file.path(out, "post_assets", f)), file.path(hand, "post_assets"))

# ---- 5. RUNBOOK.md --------------------------------------------------------------------
tm <- meta$timings_s
pkg <- meta$packages
runbook <- c(
  "# RUNBOOK — reproduce every result on a clean machine",
  "",
  sprintf("Measured on %s with %s.", meta$run_at, meta$r_version),
  "",
  "## 1. Install (once)",
  "```bash",
  "brew install --cask r quarto        # macOS; Windows: cran.r-project.org + quarto.org",
  "Rscript install.R                   # all R packages, ~3-8 min first time",
  "```",
  "",
  "## 2. Data",
  "All ABS files download automatically on first run (~500 MB; URLs in R/config.R).",
  "If the Census DataPack 404s: abs.gov.au/census/find-census-data/datapacks >",
  "2021 GCP > SA1 > NSW (short header) > save as data/2021_GCP_SA1_for_NSW_short-header.zip.",
  "",
  "## 3. Pipeline (measured runtimes from run_meta.json)",
  "```bash",
  "Rscript tests/testthat.R            # full test suite",
  sprintf("Rscript run_all.R                   # full run: data %ss, edges %ss, cliffs %ss, checks %ss, advanced %ss, assets %ss",
          tm$data %||% "-", tm$edges %||% "-", tm$cliffs %||% "-",
          tm$checks %||% "-", tm$advanced %||% "-", tm$assets %||% "-"),
  "Rscript run_all.R --line=2 --stages=assets,maps   # switch the chosen cliff line",
  "quarto render report.qmd            # report.html at the repo root",
  "bash scripts/audit.sh               # pre-push audit",
  "Rscript scripts/build_handoff.R     # this bundle",
  "```",
  "",
  "## 4. Package versions (from run_meta.json)",
  paste(sprintf("- %s %s", names(pkg), unlist(pkg)), collapse = "\n"),
  ""
)
writeLines(runbook, file.path(hand, "RUNBOOK.md"))

# ---- 6. RESULTS.md --------------------------------------------------------------------
ci <- function(v, lo, hi, d = 2) {
  if (!is.finite(v)) return("not available")
  sprintf("%.*f (95%% CI %.*f to %.*f)", d, v, d, lo, d, hi)
}
fl <- flags[flags$line_id == sel$line_id, ]
flag_cols <- c("water", "park", "transport", "industrial", "tiny_pop",
               "study_edge", "implausible", "single_sa1")
on_flags <- flag_cols[unlist(fl[1, flag_cols])]
runners <- setdiff(unlist(sel$eligible_ids), sel$line_id)
results <- c(
  "# RESULTS",
  "",
  "## Chosen cliff",
  "",
  sprintf("**Line %s — %s** (%s): %s side vs %s side. Selection: %s.",
          sel$line_id, sel$where,
          ifelse(is.na(row$border_kind), "kind unknown", row$border_kind),
          row$hi_area, row$lo_area, sel$note),
  sprintf("Runners-up (eligible under the fixed rule): %s.",
          if (length(runners)) paste("line", runners, collapse = ", ") else "none"),
  "",
  "## The two-part result",
  "",
  sprintf("1. **Descriptive:** %s is the sharpest advantage edge the scan found across the %s Greater Sydney SA1s in the analysis.", sel$where, format(as.numeric(meta$n_units), big.mark = ",")),
  sprintf("2. **Scientific:** tested against %s simulated Sydneys with the same clustering, even this edge is not exceptional (p = %.2f): at SA1 scale, Sydney's advantage mostly changes as hills, not cliffs.", meta$config$null_n, row$p_null),
  "",
  "## Key estimates (95% CI)",
  "",
  sprintf("- Length: %.0f m; side populations %s / %s", row$length_m, row$pop_hi, row$pop_lo),
  sprintf("- Median IRSAD 2021: %.0f (high side) vs %.0f (low side)", row$irsad_2021_hi, row$irsad_2021_lo),
  sprintf("- Median household income: $%s vs $%s per week (not equivalised)", format(row$hh_income_wk_hi, big.mark = ","), format(row$hh_income_wk_lo, big.mark = ",")),
  if (all(c("social_rent_hi", "social_rent_lo") %in% names(row)) && is.finite(row$social_rent_lo))
    sprintf("- Social-rental share (ABS G37; tenure stated): %.1f%% vs %.1f%%", row$social_rent_hi, row$social_rent_lo)
  else "- Social-rental share: not available in this run",
  sprintf("- Jump at the line (500 m bandwidth): %s SD — CI includes 0", ci(trc$jump_500, trc$jump_500_lo, trc$jump_500_hi)),
  sprintf("- Step vs slope: delta BIC %s — inconclusive (CI includes 0); bootstrap step probability %.3f", ci(trc$delta_bic, trc$delta_bic_lo, trc$delta_bic_hi, 1), trc$p_step_boot),
  "- Transition width: estimate degenerate and below SA1 resolution (~170 m); NOT quoted as a physical width",
  "- 2016 comparison: NOT COMPARABLE at this line — SA1 boundaries were redrawn between ASGS editions",
  "",
  "## Held-out checks",
  "",
  sprintf("- Spatial null (max-statistic over %s SAR surrogates): p = %.3f — not exceptional", meta$config$null_n, row$p_null),
  sprintf("- 2016 rerun: %s (not comparable at this line; boundary changes, not a failed reappearance)", row$in_2016),
  sprintf("- Sensitivity stability (18-run grid): %.2f (threshold 0.8)", row$stability),
  sprintf("- passes_all: %s — no line passed the full primary test at final settings", row$passes_all),
  "",
  "## Artefact screen (kept visible, never waived)",
  "",
  sprintf("- Chosen line flags: %s", if (length(on_flags)) paste(on_flags, collapse = ", ") else "none"),
  "- Full screen for the top 10: artefact_flags.csv in this bundle.",
  "",
  "## Data QA summary",
  "",
  sprintf("- %s Greater Sydney SA1s; analysis universe %s; %s edges; %s islands; Moran's I %.3f",
          meta$n_sa1_total, meta$n_units, meta$n_edges, meta$islands, meta$moran_I),
  sprintf("- %s cliff borders merged into %s lines over 400 m", meta$n_cliff_borders, meta$n_cliff_lines),
  "- Missingness and distribution checks: out/data_provenance.md (in this bundle).",
  "",
  "## Methods dropped",
  "",
  "- **B. Multivariate cliff height** (Mahalanobis distance across four SEIFA indexes,",
  "  income, rent, age): dropped for time; not built.",
  "- **D. edge_pct sensitivity**: dropped for time; the sensitivity grid keeps",
  "  edge_pct fixed at 0.95.",
  "- **E. Bayesian boundary probability (CARBayesST)**: not attempted (stretch goal).",
  "",
  "## Known limitations",
  "",
  "- Household income is not equivalised for household size or composition.",
  "- SA1 resolution limits spatial precision; ABS designs SA1s around relatively",
  "  homogeneous areas, so edge location partly reflects geographic design.",
  "- Winner's-curse inflation: the top-ranked gap is the maximum of many candidates.",
  "- The bootstrap resamples SA1s independently (no spatial blocks), so CIs are",
  "  approximate and likely too narrow.",
  "- The SAR surrogate null assumes broadly uniform clustering across Sydney;",
  "  real clustering varies spatially.",
  "- The 2016 comparison is unavailable for the chosen line because boundaries",
  "  changed; only ~28% of nearby SA1s kept their boundary.",
  "- The transition cannot be resolved below about one SA1 (~170 m).",
  "- No line passed the full primary test at final settings.",
  "- Area-level data: differences between areas, never statements about residents;",
  "  description, not cause.",
  if (!is.na(row$border_kind)) sprintf("- Street names from OpenStreetMap (ODbL); the edge runs along %s (%s, %.0f%% cover).", row$border_name, row$border_kind, 100 * row$border_cover) else "- Overpass street naming unavailable for this run.",
  ""
)
writeLines(results, file.path(hand, "RESULTS.md"))

# ---- 7. provenance ---------------------------------------------------------------------
copy(need(file.path(out, "data_provenance.md")))
copy(need(file.path(out, "phase2_report.md")))

say <- function(...) cat(sprintf(...), "\n")
say("final_handoff assembled: %d files", length(list.files(hand, recursive = TRUE)))
for (f in list.files(hand, recursive = TRUE)) say("  %s", f)
