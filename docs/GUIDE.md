# Sydney's Cliffs: step-by-step guide (VS Code)

This guide takes you from an empty laptop to a pushed repository. Every command is listed
with what it does, and every file is explained block by block. Work through the parts in
order. Each part ends with a **Check** you must see before moving on.

- Part 1. Install the tools (once)
- Part 2. Open the project in VS Code
- Part 3. Prove it works with no internet data (tests + synthetic demo)
- Part 4. Run on real Sydney data (tonight)
- Part 5. Saturday 11 am: key, Microburbs check, final run
- Part 6. Report, videos and the push
- Part 7. How the code works, file by file
- Part 8. Troubleshooting

---

## Part 1. Install the tools (once)

You need four things: R, Quarto, Git and VS Code. Commands below are for macOS with Homebrew;
Windows links are given beside each.

| Command | What it does |
|---|---|
| `brew install --cask r` | Installs R, the language the pipeline is written in. Windows: download from cran.r-project.org |
| `brew install --cask quarto` | Installs Quarto, which turns `report.qmd` into `report.html`. Windows: quarto.org |
| `brew install git` | Installs Git (macOS often has it already: `git --version`) |
| `brew install --cask visual-studio-code` | Installs VS Code. Windows: code.visualstudio.com |
| `brew install gdal` | Optional on macOS: system GDAL. The CRAN `sf` binary includes its own, so only needed if `sf` fails to install |

**Check:** each of these prints a version.

```bash
R --version        # R 4.3 or newer
quarto --version   # 1.4 or newer
git --version
```

---

## Part 2. Open the project in VS Code

1. Unzip `sydney-cliffs.zip` somewhere simple, for example `~/code/sydney-cliffs`.
2. In VS Code: **File → Open Folder…** and choose that folder.
3. VS Code shows "This workspace has extension recommendations". Click **Install All**. That
   installs:
   - **R** (REditorSupport.r): run R lines with Ctrl/Cmd+Enter, hover help, autocomplete.
   - **Quarto**: preview and render `report.qmd`.
4. Open the terminal: **Terminal → New Terminal** (Ctrl+` ). It opens in the project folder.

| Command | What it does |
|---|---|
| `cd ~/code/sydney-cliffs` | Moves the terminal into the project folder (VS Code usually does this for you) |
| `git log --oneline` | Lists the 9 commits already made, so you can see the history |
| `git status` | Shows the working tree is clean: nothing changed, nothing staged |
| `Rscript install.R` | Installs every R package the project needs and prints their versions. Takes 2 to 10 minutes the first time |

**Check:** `Rscript install.R` ends with a list of packages and versions and no error.

Tip: every main command also exists as a button. **Terminal → Run Task…** shows tasks 1 to 7
(install, test, demo, fast run, full run, render, audit), defined in `.vscode/tasks.json`.

---

## Part 3. Prove it works (no real data needed)

| Command | What it does |
|---|---|
| `Rscript tests/testthat.R` | Runs 52 automated tests in about 40 seconds. They build a fake 30 × 30 grid of "SA1s" with a known cliff, a single outlier and a smooth gradient, then check the method finds the cliff and nothing else |
| `Rscript scripts/demo_synthetic.R` | Runs the whole pipeline on the fake grid: edges, LISA, cliffs, all three checks, the 3D map pages and the report. Writes to `demo/` (ignored by git) |
| `open demo/report_demo.html` | Opens the demo report (Windows: `start demo\report_demo.html`). It has a yellow "SYNTHETIC DATA" banner |
| `open demo/out/maps/cliff_01.html` | Opens the 3D map of the planted cliff. Add `?vertical` to the end of the address bar URL for a 9:16 phone frame. Space pauses the camera |

**Check:**
- tests end with `== DONE ==` and no `Failed` section
- the demo log says `1 cliff lines >= 400 m`
- the report says the cliff passes all three checks
- the map shows an orange block and a blue block with a red line between them

If the map page is blank, the computer is offline (deck.gl loads from the internet when the
page opens).

---

## Part 4. Run on real Sydney data (tonight)

### 4.1 Download step

```bash
Rscript run_all.R --fast --offline
```

- `run_all.R` is the entry point. On first run it downloads the ABS files into `data/` (about
  1 GB in total: SA1 boundaries, mesh blocks, SEIFA 2021, SEIFA 2016, Census DataPack).
- `--fast` uses fewer permutations (999 instead of 9,999) and fewer surrogate maps, so you get
  a first look in minutes. **Never quote numbers from a fast run.**
- `--offline` skips the OpenStreetMap lookup, so the first run does not depend on Overpass.

If the Census DataPack download fails, the error tells you exactly where to save the file:
1. Go to https://www.abs.gov.au/census/find-census-data/datapacks
2. Under *2021 General Community Profile for Statistical Area 1 (SA1)*, click **New South Wales**
   (short header)
3. Save it as `data/2021_GCP_SA1_for_NSW_short-header.zip`
4. Rerun the same command. Every other file is already cached, so it resumes.

**Check:** the log prints lines like

```
universe: N SA1s (pop >= 100, residential >= 50%)
analysis graph: N SA1s, N edges, N islands
headline: Moran's I = 0.xx, N cliff borders, N cliff lines >= 400 m
done. Top cliffs: out/cliffs_top.csv
```

Open `out/cliffs_top.csv` in VS Code (or Excel). Each row is one cliff line, with the area names
on each side, the values on each side, its length and score.

### 4.2 Sanity check before trusting it (5 minutes, do not skip)

Pick two SA1s from the top cliff and compare with ABS QuickStats. These two commands print
them:

```bash
Rscript -e 'x <- readRDS("out/cliffs_headline.rds"); b <- x$borders[x$borders$line_id == 1, ][1, ]; print(x$units$sa1_code[c(b$hi_unit, b$lo_unit)])'
```

- `readRDS("out/cliffs_headline.rds")` loads the saved cliff result.
- `x$borders[x$borders$line_id == 1, ][1, ]` takes the first border of cliff line 1.
- `x$units$sa1_code[c(b$hi_unit, b$lo_unit)]` prints the SA1 codes on the high and low side.

Search those codes on https://www.abs.gov.au/census/find-census-data/quickstats and confirm
the median household income roughly matches the `hh_income_wk_hi` / `_lo` columns.

### 4.3 Full run (leave it going overnight)

```bash
Rscript run_all.R --force=cliffs,checks
```

- No `--fast`: 9,999 permutations, 99 surrogate maps, the full 18-run sensitivity grid.
- `--force=cliffs,checks` throws away the fast checkpoints and recomputes them properly. The
  data and edges checkpoints are reused, because they do not change.
- Without `--offline`, it also asks OpenStreetMap what runs along each top cliff (road name,
  railway, water, park). Results are cached in `data/osm/`.
- Expected time on a laptop: roughly 30 to 90 minutes, mostly the surrogate maps. This is an
  estimate, not measured on real data.

**Check:** `out/cliffs_top.csv` now has `border_kind`, `border_name`, `p_null`, `in_2016`,
`stability` and `passes_all` columns. Send Durand the top 10 rows where `passes_all` is TRUE.

### 4.4 Commit nothing yet

`git status` should still say clean. Everything you produced is in `data/` and `out/`, which
git ignores on purpose.

---

## Part 5. Saturday 11 am

### 5.1 Add the key

| Command | What it does |
|---|---|
| `cp .Renviron.example .Renviron` | Makes your private settings file from the template (Windows: `copy`) |
| (edit `.Renviron` in VS Code) | Paste the key after `MICROBURBS_API_KEY=`, save |
| `git status` | Must NOT list `.Renviron`. It is ignored, so the key can never be committed |
| `Rscript -e 'nchar(Sys.getenv("MICROBURBS_API_KEY"))'` | Prints the key length (not the key), proving R can see it |

### 5.2 Microburbs second-source check (only if a top cliff is inside the City of Sydney)

```bash
Rscript -e 'for (f in list.files("R", full.names=TRUE, pattern="[.]R$")) source(f); str(mb_suburbs(), max.level = 2)'
```

- Loads the project functions, then calls `/v1/suburbs/list` to confirm the key works.
- A 403 response means outside coverage, `unavailable` means the API returned `data: null`.

Then for the two suburbs on each side of the cliff:

```bash
Rscript -e 'for (f in list.files("R", full.names=TRUE, pattern="[.]R$")) source(f); str(mb_suburb_market("Surry Hills"), max.level = 3)'
```

Look at the structure it prints, find the median price field, and note both sides' values for
the report. Responses are cached in `data/microburbs/` (ignored by git).

### 5.3 Lock the finding (by 1 pm)

Choose the cliff with Durand using these rules:
1. `passes_all` is TRUE.
2. Prefer `border_kind` road or rail (water and park cliffs are unsurprising).
3. Prefer a name people know.

Open its map: `open out/maps/cliff_01.html?vertical` (change the number to the chosen
`line_id`). Record 20 to 30 seconds with QuickTime (**File → New Screen Recording**) or OBS,
and send the clip to Durand.

---

## Part 6. Report, videos and the push

| Command | What it does |
|---|---|
| `quarto render report.qmd` | Builds `report.html` from `out/`. One self-contained file, opens offline |
| `open report.html` | Read it end to end. Every number comes from `out/` |
| (copy `demo.mp4` and `pitch.mp4` into the folder) | Durand's post and pitch videos |
| `bash scripts/audit.sh` | Pre-push audit. Must end `AUDIT PASSED`: no key, no data files in the tree or the history, both videos present and under 95 MB |

Then commit and push:

| Command | What it does |
|---|---|
| `git add report.html demo.mp4 pitch.mp4 README.md` | Stages only the hand-in files, named one by one (never `git add .` on the day) |
| `git status` | Shows exactly what will be committed. Nothing from `data/` or `out/` |
| `git commit -m "docs: final report, post and pitch"` | Records the snapshot locally |
| `gh repo create sydney-cliffs --public --source . --push` | Creates the public GitHub repo and pushes in one step (needs the GitHub CLI: `brew install gh`, then `gh auth login`) |
| *or* `git remote add origin https://github.com/<you>/sydney-cliffs.git` | Without `gh`: create an empty public repo on github.com first, then link it |
| `git push -u origin main` | Uploads the commits; `-u` makes future `git push` know where to go |

**Check:** open the repo URL in a private browser window. You see README, report.html, both
videos, and no `data/` or `out/` folder.

---

## Part 7. How the code works, file by file

The pipeline is five stages. Each stage is a file in `R/`, and `R/pipeline.R` runs them in
order, saving a checkpoint after each so a crash resumes instead of restarting.

```
data.R  ->  edges.R  ->  cliffs.R  ->  streets.R + checks.R  ->  maps.R + report.qmd
ABS files   neighbours    clusters      names + proof            pictures + write-up
```

### `R/config.R`: every setting in one place

- `cliffs_config()` returns a list of every tunable value. Nothing else in the code has a
  hard-coded number, so the report prints exactly what was used.
  - `pop_floor = 150`: SA1s with fewer residents are dropped, because ABS adds small random
    noise to protect privacy and tiny counts swing wildly.
  - `min_residential = 0.2`: drop SA1s that are mostly parks, industry or airport, using the
    ABS mesh block land-use category (0.5 fragmented the real Sydney graph).
  - `min_border_m = 50`: two SA1s are neighbours only if they share 50 m of boundary.
  - `lisa_order = 2`: LISA looks at neighbours and neighbours-of-neighbours (see cliffs.R for
    why).
  - `lisa_nsim = 9999`: permutations per SA1 for the LISA p-value.
  - `fdr_q = 0.05`: false discovery rate for the Benjamini-Hochberg correction.
  - `edge_pct = 0.95`: a cliff border's side gap must be in the top 5% of all borders.
  - `min_line_m = 400`, `line_gap_m = 150`: cliff length and merge tolerance.
  - `null_n = 99`, `grid = ...`: sizes of the checks.
- `cliffs_sources()` holds every download URL, each verified against ABS pages on 6 November,
  except the DataPack link, which is marked UNVERIFIED and has a manual fallback.
- `cliffs_paths()` says where `data/` and `out/` live.

### `R/utils.R`: small helpers

- `log_step()`: timestamped progress messages.
- `assert_that()`: stops with a clear message when an assumption is broken. Used everywhere
  instead of letting bad data flow on silently.
- `download_cached()`: downloads a file once into `data/`; later runs reuse it. On failure it
  deletes the partial file and tells you where to save it by hand.
- `unzip_once()`, `find_file()`: unzip and locate files without guessing folder names.
- `percentile_in()`: rank of a value within a reference set (used to rank border gaps).
- `connected_components()`: groups touching cliff borders into lines (union-find).

### `R/data.R`: build one SA1 table

- `parse_seifa_sheet()`: finds the column of 11-digit SA1 codes, takes IRSAD three columns to
  the right (true for both the 2016 and 2021 files), and refuses the result if the mean is not
  near 1000. If ABS changes the layout, it stops instead of returning junk.
- `parse_g01()`, `parse_g02()`: read population and the medians (household income, rent, age).
  ABS writes 0 for suppressed medians, so 0 becomes missing, not $0.
- `residential_share()`: share of each SA1's land in Residential mesh blocks.
- `build_sa1()`: downloads everything, keeps Greater Sydney (`GCC_CODE21 == "1GSYD"`), projects to
  metres (EPSG:7856, GDA2020 MGA zone 56), joins all tables and writes `out/sa1.gpkg`.
- `filter_units()`: applies the population and residential filters.

### `R/edges.R`: who borders whom

- `build_edges()`:
  1. turns each SA1 polygon into its boundary line (`st_boundary`),
  2. intersects all boundaries with each other in one call (`st_intersection(b, b)`), which
     uses a spatial index, so it is fast,
  3. keeps line pieces only (a corner touch is a point and drops out),
  4. adds up the shared length per pair and keeps pairs with at least `min_border_m`.
  The result is a table of pairs `(i, j)`, their shared border as a line, and its length.
- `edges_to_nb()`: converts that table into the `nb` neighbour-list format the `spdep`
  package expects.

### `R/cliffs.R`: the method

`find_cliffs()` runs in six steps:

1. **Transform.** `transform_var()` applies log to money, logit to shares, nothing to scores.
   `standardise()` turns values into z-scores (mean 0, sd 1).
2. **Clusters.** `run_lisa()` computes Local Moran's I for every SA1 with `spdep::localmoran_perm`
   (conditional permutation p-values), adjusts the p-values with Benjamini-Hochberg
   (`p.adjust(method = "BH")`) and labels each SA1 HH, LL, HL, LH or ns.
   - Why second-order neighbours (`lisa_order = 2`)? With only 4 to 6 direct neighbours, a
     permutation test has little power, and after correcting for 12,000 tests almost nothing
     is significant. The tests showed this on the synthetic grid. Second-order neighbourhoods
     give enough power while staying local.
3. **Side gaps.** `side_gaps()` gives every border `(i, j)` two sides:
   - side i = i plus its neighbours, minus j and j's neighbours,
   - side j = the same the other way round.
   It returns the difference between the two side means. One odd SA1 cannot make a big side
   gap, because its side is averaged with its ordinary neighbours.
4. **Rank.** Each border's side gap gets a percentile among all borders in Sydney.
5. **Cluster support (Durand's rule).** `side_support()` keeps a border only if the high side
   holds a significant HH SA1 and the low side a significant LL SA1. So a cliff is always two
   real clusters meeting, never one outlier.
6. **Lines.** `merge_cliff_lines()` joins cliff borders within 150 m into one line, drops lines
   under 400 m, and scores each line as `median side gap (SD units) × log(length)`, an absolute jump size that the null test can compare across maps. It also records
   the values and area names on each side.

### `R/checks.R`: is it real?

- **Spatial null** (`calibrate_rho`, `sar_surrogate`, `null_max_scores`, `null_pvalues`):
  - Shuffling values randomly would destroy Sydney's real clustering and make every cliff look
    significant. Instead we generate surrogate maps from a spatial autoregressive model,
    `y = (I − ρW)⁻¹ e`, choosing ρ by bisection so the surrogates have the same global Moran's I
    as the real map.
  - The whole cliff search reruns on every surrogate, keeping its best score.
  - A real cliff's p-value is `(1 + number of surrogates whose best ≥ ours) / (1 + surrogates)`.
    Comparing against each surrogate's best, not an average, corrects for the fact that we
    searched thousands of borders.
- **Time** (`check_time`): reruns on SEIFA 2016 using only SA1s whose boundaries did not change
  (`change_flag == "0"`), so no boundary conversion is needed. Values are standardised within
  each year, because ABS says raw SEIFA scores should not be compared across releases.
- **Sensitivity** (`check_sensitivity`): 18 reruns (population floor 100/150/300 × minimum border
  25/50/100 m × FDR 0.05/0.01). Edges are built once at the loosest setting and subset for each
  run, so this takes minutes, not hours. Stability = share of runs where the cliff is still in
  the top 20.
- `reappears()`: "the same cliff" means a line within 200 m.

### `R/streets.R`: what runs along the cliff

- `overpass_ql()` writes an OpenStreetMap query for roads, railways, water and parks in a small
  box around the cliff.
- `fetch_overpass()` sends it (max one request every 2 seconds, retries) and caches the answer
  in `data/osm/`.
- `parse_overpass()` turns the answer into lines tagged road, rail, water or park.
- `classify_lines()` buffers each cliff by 30 m and picks the feature with the most length
  inside: that is the road or railway the cliff follows.

### `R/microburbs.R`: the API client

- `mb_key()` reads the key from the environment only; it is never written in code.
- `mb_request()` adds the bearer token, limits to 8 requests per second, retries on 429, and
  never throws on an HTTP error, so `mb_parse()` can map every case:
  `403 → outside`, `data: null → unavailable`, otherwise `ok`.
- `mb_cached()` stores responses under `data/microburbs/` (ignored by git).

### `R/maps.R` and `R/map_template.html`: the 3D wall

- `write_cliff_map()` takes SA1s within 1.5 km of the cliff, sets each one's height from its
  percentile, colours HH orange and LL blue, embeds them as GeoJSON in the HTML template and
  points the camera across the cliff (`line_bearing`) so the wall faces you.
- The template loads deck.gl and MapLibre from a CDN, draws the extruded areas and the red
  cliff line, adds the title, legend and credits, and slowly sways the camera for recording.

### `R/pipeline.R`: running it all

- `cliffs_variables()` lists the variables: SEIFA IRSAD is the headline; income, rent and age
  describe what changes across each cliff.
- `checkpoint()` saves each stage's result as `.rds` and reloads it next time. `--force=`
  recomputes a stage (`edges`, `cliffs`, `streets`, `checks`, `advanced`).
- The `advanced` stage (`R/advanced.R`) adds the step-vs-slope transect test and the
  2016 vs 2021 side-gap change for each top line, writing `out/transects.csv` and
  `out/transect_points.csv` and merging the summary into `out/cliffs_top.csv`.
- `profile_lines()` gives each cliff its side-by-side numbers on every variable.
- `run_pipeline()` runs the stages, joins everything into `out/cliffs_top.csv`, writes
  `out/cliffs.gpkg` (layers `lines` and `lisa`), the map pages, and `out/run_meta.json` with the
  settings, counts, timings and package versions.

### `run_all.R`

Reads the flags (`--fast`, `--offline`, `--stages=`, `--force=`), loads every file in `R/`, and
calls `run_pipeline()`.

### `report.qmd`

Quarto source of `report.html`. Every sentence with a number is generated from `out/`, so the
report cannot disagree with the analysis. Sections: Finding, Data, Method, Held-out checks,
What worked, What did not work, Limits. With `-P synthetic:true` it shows the synthetic banner.

### `tests/`

- `helper-load.R` loads the project before the tests.
- `test-method.R` (22 checks): rook edges and border lengths, LISA recovers both clusters, the
  planted cliff is found at the right x position and near full length, the outlier never forms
  a cliff, a smooth gradient gives no cliff, results repeat with the same seed, surrogates match
  the observed Moran's I, the planted cliff beats every surrogate.
- `test-parsers.R` (19 checks): both SEIFA layouts, a broken layout is refused, suppressed zeros
  become missing, Overpass classification, every Microburbs status, the key is never
  hard-coded.
- `test-pipeline.R` (11 checks): a full offline run on synthetic data produces every output,
  every map placeholder is filled, and a second run hits the checkpoints with identical
  results.

### `scripts/`

- `demo_synthetic.R`: the full pipeline plus report on synthetic data, no downloads.
- `audit.sh`: the pre-push guard used in Part 6.

### Hidden files

- `.gitignore`: keeps keys, `data/`, `out/`, `demo/` and every data format out of git.
- `.Renviron.example`: template for the key file.
- `.vscode/`: recommended extensions, editor settings and the Run Task buttons.

---

## Part 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `install.packages` fails on `sf` | Missing system libraries (Linux) | macOS/Windows: use the CRAN binary (default). Linux: `sudo apt install libgdal-dev libgeos-dev libproj-dev libudunits2-dev` |
| `Download failed for 2021_GCP_SA1_for_NSW_short-header.zip` | The DataPack link differs | Download it by hand (Part 4.1) |
| `SEIFA 2021: IRSAD mean ... is not near 1000` | ABS changed the spreadsheet layout | Open the xlsx, find the IRSAD column, adjust `code_col + 3` in `parse_seifa_sheet()` |
| `G02: missing columns` | Long-header DataPack downloaded | Download the **short header** version |
| Very few or zero cliff lines | Settings too strict for real data | Try `edge_pct = 0.9` in `R/config.R`, rerun with `--force=cliffs,checks`, and say so in the report |
| Overpass errors or timeouts | Public server busy | Rerun later, or use `--offline` and name the street by looking at the map |
| Map page blank | Offline, or the CDN is blocked | Open it with internet access |
| `MICROBURBS_API_KEY is not set` | `.Renviron` missing or R started elsewhere | Run from the project folder; restart the VS Code terminal after creating `.Renviron` |
| Audit fails on data in history | A data file was committed at some point | Do not push. Ask before rewriting history |
