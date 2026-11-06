# Sydney's Cliffs

**Where crossing one street puts you in a different Sydney.**

Microburbs hackathon, 7 November 2026 · Task 1 (social post) · Jaideep and Durand

## What we built

A reproducible R pipeline that scans every neighbourhood border in Greater Sydney and finds
**cliffs**: places where an advantaged cluster of neighbourhoods directly meets a
disadvantaged one. The steepest cliff that survives our checks becomes the social post
(`demo.mp4`), with a 3D map where the cliff stands up as a wall.

## Who it helps

- **Home buyers and renters**: suburb averages hide street-level differences. A cliff shows
  exactly where the change happens.
- **Councils and planners**: sharp boundaries in advantage mark where services and
  investment decisions matter most.
- **Microburbs**: the same engine runs on any area-level layer, so it can turn their data into a
  recurring series of posts.

## The clever step

Finding a big difference between two neighbours is easy, and usually means one odd area.
We only count a border as a cliff when **two real clusters meet**:

1. **Clusters.** Local Moran's I (LISA) with 9,999 conditional permutations on second-order
   neighbourhoods, then Benjamini-Hochberg FDR correction across all SA1s.
2. **Borders, not areas.** Each shared border splits its neighbourhood into two sides. A border
   is a cliff border when the gap between the two side means is in the top 5% of all Sydney
   borders, **and** the high side contains a significant High-High area and the low side a
   significant Low-Low area. A lone outlier cannot pass this test.
3. **Lines.** Cliff borders within 150 m merge into lines; lines under 400 m are dropped.
4. **Proof (our held-out checks):**
   - *Spatial null*: 99 surrogate maps from a SAR process calibrated to Sydney's real global
     Moran's I. Each real cliff is compared with the best cliff found in every surrogate
     (max-statistic, so it controls for searching thousands of borders).
   - *Time*: the same search on SEIFA 2016, using only SA1s whose boundaries did not change.
   - *Sensitivity*: 18 reruns across population floor, minimum border length and FDR level.

The test suite plants a cliff, an outlier and a smooth gradient in a synthetic grid and checks
that the method finds the cliff and nothing else (`tests/testthat/test-method.R`).

## Data

| Source | Used for | Licence |
|---|---|---|
| ABS, Socio-Economic Indexes for Areas (SEIFA) 2021 and 2016, SA1, IRSAD | Headline variable | CC BY 4.0, © Commonwealth of Australia |
| ABS, 2021 Census General Community Profile DataPack, SA1, NSW (G01, G02) | Population, household income, rent, age | CC BY 4.0, © Commonwealth of Australia |
| ABS, ASGS Edition 3 (2021) SA1 and Mesh Block boundaries | Areas, residential land share, boundary change flags | CC BY 4.0, © Commonwealth of Australia |
| OpenStreetMap via the Overpass API | Naming the road, railway, water or park along each cliff | ODbL, © OpenStreetMap contributors |
| CARTO basemap (map pages only) | Background map in the 3D renders | © CARTO, © OpenStreetMap contributors |
| Microburbs API (hackathon key) | Second-source check for cliffs inside the City of Sydney | Used on the day only; no API output is stored in this repository |

No supplied hackathon files, API output, licensed data rows or keys are committed. All data is
downloaded into `data/` and derived into `out/`, both ignored by git.

Every figure in the post comes from `out/cliffs_top.csv`, which is produced by `run_all.R`
from the sources above.

## How to run

Requirements: R 4.3+, Quarto 1.4+, Git. VS Code with the R and Quarto extensions is recommended.

```bash
Rscript install.R               # install packages (one-off)
Rscript tests/testthat.R        # 52 tests, about 40 seconds
Rscript scripts/demo_synthetic.R  # full pipeline on synthetic data, no downloads
Rscript run_all.R --fast        # real Sydney data, quick look
Rscript run_all.R               # real Sydney data, full permutations and checks
quarto render report.qmd        # builds report.html from out/
```

Optional: copy `.Renviron.example` to `.Renviron` and add `MICROBURBS_API_KEY` for the
Microburbs check. In VS Code, every command above is also available under
**Terminal → Run Task**.

## Repository layout

```
R/config.R        every tunable value and source URL
R/data.R          download and tidy ABS inputs -> out/sa1.gpkg
R/edges.R         neighbour pairs and shared-border lines
R/cliffs.R        LISA, side gaps, cliff borders, cliff lines
R/checks.R        spatial null, 2016 rerun, sensitivity grid
R/streets.R       OpenStreetMap lookup of what runs along each cliff
R/microburbs.R    Microburbs API client (key from environment only)
R/maps.R          3D map page per cliff (deck.gl), for screen recording
R/pipeline.R      orchestration with resumable checkpoints
run_all.R         command-line entry point
report.qmd        source of report.html
tests/            synthetic-data tests for method, parsers and pipeline
scripts/          synthetic demo and pre-push audit
```

## Limits

Area-level data describes neighbourhoods, not individuals. A cliff shows where things change,
not why. Census figures are from 2021.
