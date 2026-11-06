# Stage 5: is each cliff real? Three independent checks.
#
#  (a) Spatial null. Shuffling values across areas destroys spatial structure, so
#      on a smooth map almost any neighbour gap looks extreme. Instead we simulate
#      surrogate maps from a simultaneous autoregressive (SAR) process whose rho is
#      calibrated so the surrogates have the same global Moran's I as the real
#      data, then rerun the full cliff search on each. Each real cliff is compared
#      with the BEST cliff in every surrogate (max-statistic), which controls the
#      family-wise error across all candidate lines.
#  (b) Time. Rerun on SEIFA 2016, restricted to SA1s whose boundary did not change
#      between ASGS 2016 and 2021 (change_flag == "0"). ABS advises against
#      comparing SEIFA scores across years, so both years are standardised within
#      year and only the cluster pattern is compared.
#  (c) Sensitivity grid. Rerun across population floors, minimum border lengths
#      and FDR levels; report the share of runs where the cliff stays in the top 20.

# ---- (a) SAR surrogate null ------------------------------------------------------

sar_surrogate <- function(nb, rho, n_draws, seed) {
  W  <- row_std_sparse(nb)  # sparse: n can be 12k+
  A  <- Matrix::Diagonal(nrow(W)) - rho * W
  set.seed(seed)
  E  <- matrix(stats::rnorm(nrow(W) * n_draws), ncol = n_draws)
  Y  <- as.matrix(Matrix::solve(A, E))
  apply(Y, 2, standardise)
}

# Row-standardised sparse weights straight from an nb list (islands = zero rows).
row_std_sparse <- function(nb) {
  card <- vapply(nb, function(v) sum(v > 0), integer(1))
  i <- rep(seq_along(nb), card)
  j <- unlist(lapply(nb, function(v) v[v > 0]))
  Matrix::sparseMatrix(i = i, j = j, x = 1 / card[i], dims = c(length(nb), length(nb)))
}

calibrate_rho <- function(nb, target_I, seed, tol = 0.01, draws = 5) {
  f <- function(rho) mean(apply(sar_surrogate(nb, rho, draws, seed), 2, global_moran, nb = nb)) - target_I
  lo <- 0; hi <- 0.99
  if (f(hi) < 0) return(hi)
  for (k in 1:30) {
    mid <- (lo + hi) / 2
    v <- f(mid)
    if (abs(v) < tol) return(mid)
    if (v > 0) hi <- mid else lo <- mid
  }
  (lo + hi) / 2
}

# res: output of find_cliffs() on the real data. Returns the max cliff score of
# each surrogate map (0 when a surrogate has no cliff line).
null_max_scores <- function(res, cfg) {
  units <- res$units
  edges_all <- res$edges
  nb <- edges_to_nb(edges_all, nrow(units))
  rho <- calibrate_rho(nb, res$moran_I, seed = cfg$seed)
  log_step(sprintf("null: calibrated SAR rho = %.3f to match Moran's I = %.3f", rho, res$moran_I))
  Y <- sar_surrogate(nb, rho, cfg$null_n, seed = cfg$seed + 1)
  vapply(seq_len(ncol(Y)), function(k) {
    u <- units; u$.sim <- Y[, k]
    r <- find_cliffs(u, edges_all, ".sim", "score", nsim = cfg$null_nsim, q = cfg$fdr_q,
                     min_line_m = cfg$min_line_m,
                     edge_pct = cfg$edge_pct, lisa_order = cfg$lisa_order, line_gap_m = cfg$line_gap_m, seed = cfg$seed + k)
    if (nrow(r$lines) == 0) 0 else max(r$lines$score)
  }, numeric(1))
}

null_pvalues <- function(scores, null_max) {
  vapply(scores, function(s) (1 + sum(null_max >= s)) / (1 + length(null_max)), numeric(1))
}

# ---- (b) and (c) shared: does a cliff reappear? --------------------------------------

reappears <- function(lines, other_lines, dist_m) {
  if (nrow(lines) == 0) return(logical())
  if (nrow(other_lines) == 0) return(rep(FALSE, nrow(lines)))
  lengths(sf::st_is_within_distance(lines, other_lines, dist = dist_m)) > 0
}

check_time <- function(units, edges, lines, cfg) {
  keep <- units$change_flag == "0" & is.finite(units$irsad_2016)
  g <- subset_graph(units, edges, keep)
  r16 <- find_cliffs(g$units, g$edges, "irsad_2016", "score", nsim = cfg$grid_nsim,
                     q = cfg$fdr_q, min_line_m = cfg$min_line_m,
                     edge_pct = cfg$edge_pct, lisa_order = cfg$lisa_order, line_gap_m = cfg$line_gap_m, seed = cfg$seed)
  reappears(lines, r16$lines, cfg$match_dist_m)
}

# base_units / base_edges: built once with the loosest grid settings (lowest
# population floor, shortest border). Shared borders do not change when areas are
# dropped, so every grid cell is a subset: no edge rebuilds.
check_sensitivity <- function(base_units, base_edges, lines, var, type, cfg) {
  grid <- expand.grid(cfg$grid, KEEP.OUT.ATTRS = FALSE)
  hits <- matrix(FALSE, nrow(lines), nrow(grid))
  for (r in seq_len(nrow(grid))) {
    p <- grid[r, ]
    log_step(sprintf("sensitivity %d/%d: pop>=%d border>=%dm q=%.2f",
                     r, nrow(grid), p$pop_floor, p$min_border_m, p$fdr_q))
    e <- base_edges[base_edges$border_m >= p$min_border_m, ]
    g <- subset_graph(base_units, e, base_units$pop >= p$pop_floor)
    rr <- find_cliffs(g$units, g$edges, var, type, nsim = cfg$grid_nsim, q = p$fdr_q,
                      min_line_m = cfg$min_line_m,
                     edge_pct = cfg$edge_pct, lisa_order = cfg$lisa_order, line_gap_m = cfg$line_gap_m, seed = cfg$seed)
    top <- utils::head(rr$lines, cfg$top_n)
    hits[, r] <- reappears(lines, top, cfg$match_dist_m)
  }
  colnames(hits) <- sprintf("pop%d_b%d_q%.2f", grid$pop_floor, grid$min_border_m, grid$fdr_q)
  list(stability = rowMeans(hits), detail = hits)
}
