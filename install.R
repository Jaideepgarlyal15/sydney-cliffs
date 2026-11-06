# One-off setup: installs every package the project needs, skipping ones you have.
#   Rscript install.R
# Tested with R 4.3+: sf 1.0, spdep 1.3, Matrix 1.6, httr2 1.0, testthat 3.2.

needed <- c(
  "sf", "spdep", "Matrix",            # spatial data, neighbours, sparse algebra
  "dplyr", "readr", "readxl",         # tables and ABS spreadsheets
  "httr2", "jsonlite",                # HTTP (ABS, Overpass, Microburbs) and JSON
  "testthat",                         # tests
  "knitr", "rmarkdown",               # Quarto's R engine
  "languageserver"                    # VS Code R extension: autocomplete, hover help
)
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}
for (p in needed) message(sprintf("  %-15s %s", p, as.character(utils::packageVersion(p))))
