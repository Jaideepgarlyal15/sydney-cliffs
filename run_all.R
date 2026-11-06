#!/usr/bin/env Rscript
# Entry point.
#   Rscript run_all.R                      # full run (downloads on first use)
#   Rscript run_all.R --fast               # quick look: fewer permutations and surrogates
#   Rscript run_all.R --offline            # skip OpenStreetMap lookups
#   Rscript run_all.R --stages=cliffs,maps # run selected stages (data, cliffs, streets, checks, maps)
#   Rscript run_all.R --force=cliffs       # recompute a checkpoint (edges, cliffs, streets, checks)

args <- commandArgs(trailingOnly = TRUE)
flag <- function(name) any(args == paste0("--", name))
value <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) strsplit(sub(paste0("^--", name, "="), "", hit[1]), ",")[[1]] else default
}

options(cliffs.root = normalizePath("."))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

cfg <- cliffs_config()
if (flag("fast")) {
  cfg$lisa_nsim <- 999; cfg$null_n <- 19; cfg$null_nsim <- 199; cfg$grid_nsim <- 199
  log_step("FAST mode: results are for exploration, rerun without --fast before quoting numbers")
}

run_pipeline(
  stages = value("stages", "all"),
  cfg = cfg,
  online = !flag("offline"),
  force = value("force", character())
)
