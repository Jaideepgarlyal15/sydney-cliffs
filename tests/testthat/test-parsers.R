# Parsers are pure functions, tested on small fixtures that mimic the real files.

test_that("SEIFA 2021 layout: code in col 1, IRSAD three columns right", {
  raw <- data.frame(
    a = c("Title", NA, "SA1 code", "11601100101", "11601100102", "11601100103"),
    b = c(NA, NA, "IRSD", 950, 1010, 1080),
    c = c(NA, NA, "Decile", 3, 6, 9),
    d = c(NA, NA, "IRSAD", 940, 1005, 1100),
    e = c(NA, NA, "Decile", 3, 6, 10)
  )
  out <- parse_seifa_sheet(raw, 2021)
  expect_equal(out$sa1_code, c("11601100101", "11601100102", "11601100103"))
  expect_equal(out$irsad_2021, c(940, 1005, 1100))
})

test_that("SEIFA 2016 layout: 7-digit column first, 11-digit second", {
  raw <- data.frame(
    a = c("SA1 7", "1100101", "1100102"),
    b = c("SA1 11", "11601100101", "11601100102"),
    c = c("IRSD", 950, 1010), d = c("Dec", 3, 6), e = c("IRSAD", 960, 1040)
  )
  out <- parse_seifa_sheet(raw, 2016)
  expect_equal(out$irsad_2016, c(960, 1040))
})

test_that("SEIFA parser refuses a shifted layout instead of returning junk", {
  raw <- data.frame(a = c("11601100101", "11601100102"), b = c(1, 2), c = c(3, 4), d = c(5, 6))
  expect_error(parse_seifa_sheet(raw, 2021), "not near 1000")
})

test_that("G02 parser treats suppressed zeros as missing", {
  df <- data.frame(SA1_CODE_2021 = c("1", "2"), Median_tot_hhd_inc_weekly = c(2100, 0),
                   Median_rent_weekly = c(650, 0), Median_age_persons = c(34, 0))
  out <- parse_g02(df)
  expect_equal(out$hh_income_wk, c(2100, NA))
  expect_equal(out$rent_wk, c(650, NA))
})

test_that("G02 parser names the missing column", {
  expect_error(parse_g02(data.frame(SA1_CODE_2021 = "1")), "Median_tot_hhd_inc_weekly")
})

test_that("G37 parser: social counts, and 'not stated' leaves the denominator", {
  df <- data.frame(SA1_CODE_2021 = c("1", "2"),
                   R_ST_h_auth_Total = c(100, 0), R_Com_Hp_Total = c(20, 5),
                   Total_Total = c(400, 210), Ten_type_NS_Total = c(30, 10))
  out <- parse_g37(df)
  expect_equal(out$social_rent, c(120, 5))
  expect_equal(out$occ_stated, c(370, 200))
})

test_that("G37 parser names the missing column", {
  expect_error(parse_g37(data.frame(SA1_CODE_2021 = "1")), "R_ST_h_auth_Total")
})

test_that("Overpass parser classifies roads, rail, water and parks", {
  js <- jsonlite::fromJSON(test_path("fixtures", "overpass.json"), simplifyVector = FALSE)
  osm <- parse_overpass(js)
  expect_equal(sort(osm$kind), c("park", "rail", "road", "water"))
  expect_equal(osm$name[osm$kind == "road"], "Example Road")
})

test_that("Microburbs responses map to explicit statuses", {
  expect_equal(mb_parse(403, "")$status, "outside")
  expect_equal(mb_parse(200, '{"data": null, "available": false}')$status, "unavailable")
  ok <- mb_parse(200, '{"data": {"median_price": 1200000}}')
  expect_equal(ok$status, "ok")
  expect_equal(ok$data$median_price, 1200000)
  expect_equal(mb_parse(500, "")$status, "http_500")
})

test_that("Microburbs key is never hard-coded", {
  withr_env <- Sys.getenv("MICROBURBS_API_KEY")
  Sys.setenv(MICROBURBS_API_KEY = "")
  on.exit(Sys.setenv(MICROBURBS_API_KEY = withr_env))
  expect_error(mb_key(), "not set")
})

test_that("utility helpers behave", {
  expect_equal(connected_components(5, c(1, 2, 4), c(2, 3, 5)), c(1, 1, 1, 4, 4))
  expect_equal(percentile_in(c(1, 5, 10), 1:10), c(0.1, 0.5, 1))
  expect_equal(transform_var(c(0.5, 0), "logit")[1], 0)
  expect_true(is.na(transform_var(0, "log")))
})
