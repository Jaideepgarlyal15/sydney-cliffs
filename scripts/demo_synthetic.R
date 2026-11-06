#!/usr/bin/env Rscript
# Proves the whole pipeline works without downloading anything:
# synthetic grid -> cliffs -> checks -> map -> report.
#   Rscript scripts/demo_synthetic.R
# Output goes to demo/ (gitignored). Numbers are NOT about Sydney.

options(cliffs.root = normalizePath("demo", mustWork = FALSE), cliffs.code_root = normalizePath("."))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

paths <- cliffs_paths("demo")
ensure_dir(paths$out)
s <- make_synthetic_sa1()
sf::st_write(s[, setdiff(names(s), c("col", "row"))], file.path(paths$out, "sa1.gpkg"),
             delete_dsn = TRUE, quiet = TRUE)

cfg <- cliffs_config()
cfg$lisa_nsim <- 999; cfg$null_n <- 39; cfg$null_nsim <- 199; cfg$grid_nsim <- 199
run_pipeline(stages = c("cliffs", "checks", "maps"), cfg = cfg, paths = paths, online = FALSE)

log_step("rendering demo report")
status <- system2("quarto", c("render", "report.qmd", "--output", "report_demo.html",
                              "-P", "out_dir:demo/out", "-P", "synthetic:true"))
if (status == 0 && file.exists("report_demo.html")) {
  file.rename("report_demo.html", file.path("demo", "report_demo.html"))
  log_step("demo report: demo/report_demo.html")
}
