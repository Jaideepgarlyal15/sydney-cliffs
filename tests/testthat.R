# Run with: Rscript tests/testthat.R   (or Ctrl+Shift+T style via the VS Code task)
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
