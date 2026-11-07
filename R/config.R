# Central configuration. Every tunable lives here so the sensitivity grid and the
# report read the same values. Change a value here, never inside a function.

cliffs_config <- function() {
  list(
    # --- Study area -----------------------------------------------------------
    gccsa_code   = "1GSYD",   # Greater Sydney
    crs_metric   = 7856,      # GDA2020 / MGA zone 56, metres
    crs_web      = 4326,

    # --- Unit filters ---------------------------------------------------------
    pop_floor          = 150, # drop SA1s with fewer usual residents
    min_residential    = 0.2, # drop SA1s where < 20% of land area is residential mesh blocks
                              # (0.5 removed 1,378 Sydney SA1s and fragmented the graph)
    min_border_m       = 50,  # drop neighbour pairs sharing less than this much border

    # --- LISA -----------------------------------------------------------------
    lisa_order  = 2,          # contiguity order for LISA neighbourhoods (power)
    lisa_nsim   = 9999,       # conditional permutations per SA1
    fdr_q       = 0.05,       # Benjamini-Hochberg false discovery rate
    seed        = 20261107,

    # --- Cliff lines ----------------------------------------------------------
    edge_pct    = 0.95,       # a cliff border's side gap is in the top 5% of all borders
    min_line_m  = 400,        # a cliff must run at least this far
    line_gap_m  = 150,        # cliff borders this close together are one cliff
    top_n       = 20,

    # --- Checks ---------------------------------------------------------------
    null_n         = 99,      # SAR surrogate maps for the max-statistic null
    null_nsim      = 499,     # LISA permutations inside each surrogate (speed)
    match_dist_m   = 200,     # a cliff "reappears" if a line lies within this distance
    grid = list(              # sensitivity grid (18 runs)
      pop_floor    = c(100, 150, 300),
      min_border_m = c(25, 50, 100),
      fdr_q        = c(0.05, 0.01)
    ),
    grid_nsim      = 999,

    # --- Selection --------------------------------------------------------------
    chosen_line_id = NA_integer_,      # NA = pick by the fixed rule in select_line();
                                       # set via --line=<id> on run_all.R to override

    # --- Advanced ---------------------------------------------------------------
    transect_radius_m = 1500,          # SA1 centroids within this of the line enter the transect
    rd_bandwidths_m   = c(300, 500, 800), # triangular-kernel bandwidths for the local-linear jump
    boot_n            = 999,           # bootstrap resamples for transect and gap-change CIs
    delta_bic_strong  = 10,            # BIC(linear) - BIC(logistic) above this = strong step evidence

    # --- External services ----------------------------------------------------
    overpass_url    = "https://overpass-api.de/api/interpreter",
    microburbs_base = "https://api-ht.microburbs.com.au",
    microburbs_rps  = 8       # stay under the documented ~10 req/s
  )
}

# Source URLs. Verified against ABS pages on 2026-11-06 unless marked otherwise.
cliffs_sources <- function() {
  list(
    sa1_2021 = "https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs/edition-3-july-2021-june-2026/access-and-downloads/digital-boundary-files/SA1_2021_AUST_SHP_GDA2020.zip",
    mb_2021  = "https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs/edition-3-july-2021-june-2026/access-and-downloads/digital-boundary-files/MB_2021_AUST_SHP_GDA2020.zip",
    seifa_2021_sa1 = "https://www.abs.gov.au/statistics/people/people-and-communities/socio-economic-indexes-areas-seifa-australia/2021/Statistical%20Area%20Level%201%2C%20Indexes%2C%20SEIFA%202021.xlsx",
    seifa_2016_sa1 = "https://www.abs.gov.au/ausstats/subscriber.nsf/log?openagent&2033055001%20-%20sa1%20indexes.xls&2033.0.55.001&Data%20Cubes&40A0EFDE970A1511CA25825D000F8E8D&0&2016&27.03.2018&Latest",
    # UNVERIFIED: the DataPacks page does not print its hrefs. This follows the
    # ABS naming pattern; 01_get_data.R falls back to manual-download instructions.
    gcp_2021_sa1_nsw = "https://www.abs.gov.au/census/find-census-data/datapacks/download/2021_GCP_SA1_for_NSW_short-header.zip",
    gcp_landing      = "https://www.abs.gov.au/census/find-census-data/datapacks"
  )
}

cliffs_paths <- function(root = getOption("cliffs.root", ".")) {
  list(
    data = file.path(root, "data"),
    out  = file.path(root, "out"),
    osm_cache = file.path(root, "data", "osm"),
    mb_cache  = file.path(root, "data", "microburbs")
  )
}
