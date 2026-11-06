# Loaded automatically by testthat before every test file.
root <- normalizePath(file.path("..", ".."))
options(cliffs.code_root = root)
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)

withr_tempdir <- function() {
  d <- tempfile("cliffs-test-")
  dir.create(d)
  d
}
