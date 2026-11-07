# Stage 1: download and tidy ABS inputs into one SA1 table (out/sa1.gpkg).
# Each reader is split into read_* (touches disk) and parse_* (pure, testable).

# ---- SEIFA -------------------------------------------------------------------

# Parse a SEIFA SA1 "Table 1" sheet read with col_names = FALSE.
# Layout differs between releases, so we locate the 11-digit SA1 code column and
# take IRSAD as the score three columns to its right (IRSD score, IRSD decile,
# IRSAD score), which holds for both the 2016 and 2021 data cubes.
parse_seifa_sheet <- function(raw, year) {
  raw <- as.data.frame(raw)
  is_code <- function(col) {
    v <- suppressWarnings(as.character(col))
    mean(grepl("^[0-9]{11}$", v[!is.na(v)])) > 0.5
  }
  code_col <- which(vapply(raw, is_code, logical(1)))
  assert_that(length(code_col) >= 1, paste("SEIFA", year, ": no 11-digit SA1 column found"))
  code_col <- code_col[[1]]
  rows <- grepl("^[0-9]{11}$", as.character(raw[[code_col]]))
  out <- data.frame(
    sa1_code = as.character(raw[[code_col]][rows]),
    irsad    = suppressWarnings(as.numeric(raw[[code_col + 3]][rows])),
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$irsad), ]
  m <- mean(out$irsad)
  assert_that(m > 850 && m < 1150,
              sprintf("SEIFA %s: IRSAD mean %.0f is not near 1000; column layout changed?", year, m))
  names(out)[2] <- paste0("irsad_", year)
  out
}

read_seifa <- function(path, year) {
  sheets <- readxl::excel_sheets(path)
  sheet <- sheets[grepl("^Table 1", sheets)][1]
  if (is.na(sheet)) sheet <- sheets[2]
  raw <- readxl::read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal")
  parse_seifa_sheet(raw, year)
}

# ---- Census G01 / G02 ----------------------------------------------------------

parse_g01 <- function(df) {
  assert_that(all(c("SA1_CODE_2021", "Tot_P_P") %in% names(df)),
              "G01: expected SA1_CODE_2021 and Tot_P_P columns (short-header DataPack)")
  data.frame(sa1_code = as.character(df$SA1_CODE_2021), pop = as.numeric(df$Tot_P_P))
}

parse_g02 <- function(df) {
  need <- c("SA1_CODE_2021", "Median_tot_hhd_inc_weekly", "Median_rent_weekly", "Median_age_persons")
  assert_that(all(need %in% names(df)),
              paste("G02: missing columns:", paste(setdiff(need, names(df)), collapse = ", ")))
  out <- data.frame(
    sa1_code     = as.character(df$SA1_CODE_2021),
    hh_income_wk = as.numeric(df$Median_tot_hhd_inc_weekly),
    rent_wk      = as.numeric(df$Median_rent_weekly),
    median_age   = as.numeric(df$Median_age_persons)
  )
  # ABS publishes 0 for medians it suppresses; treat as missing, not as $0.
  out$hh_income_wk[out$hh_income_wk <= 0] <- NA
  out$rent_wk[out$rent_wk <= 0] <- NA
  out$median_age[out$median_age <= 0] <- NA
  out
}

# G37: tenure and landlord type. Social rental = rented from a state or
# territory housing authority plus rented from a community housing provider.
# Denominator = occupied private dwellings whose tenure type is stated
# (Total_Total minus Ten_type_NS_Total), so "not stated" never dilutes a share.
parse_g37 <- function(df) {
  need <- c("SA1_CODE_2021", "R_ST_h_auth_Total", "R_Com_Hp_Total",
            "Total_Total", "Ten_type_NS_Total")
  assert_that(all(need %in% names(df)),
              paste("G37: missing columns:", paste(setdiff(need, names(df)), collapse = ", ")))
  data.frame(
    sa1_code    = as.character(df$SA1_CODE_2021),
    social_rent = as.numeric(df$R_ST_h_auth_Total) + as.numeric(df$R_Com_Hp_Total),
    occ_stated  = as.numeric(df$Total_Total) - as.numeric(df$Ten_type_NS_Total)
  )
}

read_census <- function(gcp_dir) {
  g01 <- readr::read_csv(find_file(gcp_dir, "G01_NSW_SA1\\.csv$"), show_col_types = FALSE)
  g02 <- readr::read_csv(find_file(gcp_dir, "G02_NSW_SA1\\.csv$"), show_col_types = FALSE)
  g37 <- readr::read_csv(find_file(gcp_dir, "G37_NSW_SA1\\.csv$"), show_col_types = FALSE)
  Reduce(function(a, b) merge(a, b, by = "sa1_code", all = TRUE),
         list(parse_g01(g01), parse_g02(g02), parse_g37(g37)))
}

# Population(dwelling)-weighted social-rental share (%) of the SA1s touching
# each cliff line, per side. Returns one row per line_id; NA columns when the
# table lacks G37 counts (e.g. synthetic data).
side_social_rent <- function(res, sa1_tab) {
  b <- sf::st_drop_geometry(res$borders)
  ids <- sort(unique(b$line_id[!is.na(b$line_id)]))
  out <- data.frame(line_id = ids, social_rent_hi = NA_real_, social_rent_lo = NA_real_)
  if (!all(c("social_rent", "occ_stated") %in% names(sa1_tab))) return(out)
  codes <- res$units$sa1_code
  share <- function(idx) {
    s <- sa1_tab[match(unique(codes[idx]), sa1_tab$sa1_code), ]
    d <- sum(s$occ_stated, na.rm = TRUE)
    if (d <= 0) NA_real_ else round(100 * sum(s$social_rent, na.rm = TRUE) / d, 1)
  }
  for (k in seq_along(ids)) {
    bi <- b[which(b$line_id == ids[k]), ]
    out$social_rent_hi[k] <- share(bi$hi_unit)
    out$social_rent_lo[k] <- share(bi$lo_unit)
  }
  out
}

# ---- Boundaries and land use ---------------------------------------------------

# Share of each SA1's land area made up of Residential mesh blocks.
residential_share <- function(mb) {
  mb <- sf::st_drop_geometry(mb)
  area <- as.numeric(mb$AREASQKM21)
  res  <- ifelse(mb$MB_CAT21 == "Residential", area, 0)
  agg  <- stats::aggregate(cbind(res = res, all = area) ~ SA1_CODE21, data = data.frame(
    SA1_CODE21 = mb$SA1_CODE21, res = res, all = area), FUN = sum)
  data.frame(sa1_code = agg$SA1_CODE21, resid_share = ifelse(agg$all > 0, agg$res / agg$all, 0))
}

# ---- Orchestration -------------------------------------------------------------

build_sa1 <- function(cfg = cliffs_config(), src = cliffs_sources(), paths = cliffs_paths()) {
  d <- paths$data
  sa1_zip <- download_cached(src$sa1_2021, file.path(d, "SA1_2021_AUST_SHP_GDA2020.zip"))
  mb_zip  <- download_cached(src$mb_2021,  file.path(d, "MB_2021_AUST_SHP_GDA2020.zip"))
  s21 <- download_cached(src$seifa_2021_sa1, file.path(d, "seifa_2021_sa1.xlsx"))
  s16 <- download_cached(src$seifa_2016_sa1, file.path(d, "seifa_2016_sa1.xls"))
  gcp <- download_cached(src$gcp_2021_sa1_nsw, file.path(d, "2021_GCP_SA1_for_NSW_short-header.zip"),
                         manual_hint = paste("Get 'General Community Profile, SA1, New South Wales' (short header) from",
                                             src$gcp_landing))

  log_step("reading SA1 boundaries")
  sa1 <- sf::st_read(find_file(unzip_once(sa1_zip, file.path(d, "sa1_2021")), "\\.shp$"), quiet = TRUE)
  sa1 <- sa1[sa1$GCC_CODE21 == cfg$gccsa_code & !sf::st_is_empty(sa1), ]
  sa1 <- sf::st_transform(sa1, cfg$crs_metric)
  sa1 <- data.frame(
    sa1_code = sa1$SA1_CODE21, sa2_name = sa1$SA2_NAME21,
    change_flag = as.character(sa1$CHG_FLAG21), geometry = sf::st_geometry(sa1)
  ) |> sf::st_as_sf()

  log_step("reading mesh blocks (land use)")
  mb <- sf::st_read(find_file(unzip_once(mb_zip, file.path(d, "mb_2021")), "\\.shp$"), quiet = TRUE)
  mb <- mb[mb$GCC_CODE21 == cfg$gccsa_code, ]

  log_step("joining SEIFA and Census")
  tab <- Reduce(function(a, b) merge(a, b, by = "sa1_code", all.x = TRUE), list(
    data.frame(sa1_code = sa1$sa1_code),
    residential_share(mb),
    read_seifa(s21, 2021),
    read_seifa(s16, 2016),
    read_census(unzip_once(gcp, file.path(d, "gcp_2021_sa1_nsw")))
  ))
  sa1 <- merge(sa1, tab, by = "sa1_code", all.x = TRUE)

  ensure_dir(paths$out)
  sf::st_write(sa1, file.path(paths$out, "sa1.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  log_step(sprintf("wrote out/sa1.gpkg: %d SA1s, IRSAD 2021 present for %d",
                   nrow(sa1), sum(is.finite(sa1$irsad_2021))))
  invisible(sa1)
}

# Apply the unit filters. Returned rows are the analysis universe.
filter_units <- function(sa1, pop_floor, min_residential) {
  keep <- is.finite(sa1$pop) & sa1$pop >= pop_floor &
    is.finite(sa1$resid_share) & sa1$resid_share >= min_residential
  sa1[keep, ]
}
