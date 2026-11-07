# Sydney's Cliffs

**Where crossing one street puts you in a different Sydney.**

Microburbs hackathon, 7 November 2026 · Task 1 (social post) · Jaideep and Durand

## Result

1. **Descriptive:** Young Street, Redfern is the sharpest advantage edge our scan found across the
   11,237 Greater Sydney SA1s in our analysis — 9% social housing on one side, 74% on the other (ABS Census 2021, G37; tenure-stated dwellings).
2. **Scientific:** tested against 99 simulated Sydneys with the same clustering, even that edge is
   not statistically exceptional (p = 0.34): at SA1 scale, Sydney's advantage mostly changes as hills, not cliffs.

## What we built

A reproducible R pipeline that scans every neighbourhood border in Greater Sydney for
**cliffs**: places where an advantaged cluster of neighbourhoods directly meets a
disadvantaged one — then stress-tests every candidate against simulated Sydneys and reports
the result honestly, pass or fail. The sharpest edge becomes the social post (`demo.mp4`),
with a 3D map where the edge stands up as a wall.

## Who it helps

- **Home buyers and renters**: suburb averages hide street-level differences. A cliff shows
  exactly where the change happens.
- **Councils and planners**: sharp boundaries in advantage mark where services and
  investment decisions matter most.
- **Microburbs**: the same engine runs on any area-level layer, so it can turn their data into a
  recurring series of posts.

## The clever step

1. **Two real clusters must meet.** LISA (9,999 permutations, BH-FDR) must put a significant High-High area on one side and a Low-Low area on the other; side gaps average each side's neighbourhood, so one odd area can never make a cliff.
2. **An absolute score.** Lines score by median side gap (in SD) × log(length) — comparable across maps, so the max-statistic SAR null (99 surrogates matched to Sydney's Moran's I) is a fair fight.
3. **Step, not slope.** A logistic-vs-linear BIC test on each cliff's transect says whether advantage jumps or merely tilts, with a bootstrap CI, a 10–90% width in metres, and a local-linear jump at three bandwidths.
4. **Time, handled with care.** 2016 vs 2021 side gaps are standardised within year, on unchanged-boundary SA1s only, per ABS guidance.
5. **Three held-out checks gate every claim** (SAR max-statistic null, 2016 reappearance, 18-run sensitivity grid) and an artefact screen stays visible in the outputs — flags are reported, never waived.
6. The test suite plants a cliff, an outlier and a smooth gradient in a synthetic grid and proves the method finds the cliff, the step and the planted 2016 widening — and nothing else (`tests/testthat/`).

## Data

| Source | Used for | Licence |
|---|---|---|
| ABS, Socio-Economic Indexes for Areas (SEIFA) 2021 and 2016, SA1, IRSAD | Headline variable | CC BY 4.0, © Commonwealth of Australia |
| ABS, 2021 Census General Community Profile DataPack, SA1, NSW (G01, G02) | Population, household income, rent, age | CC BY 4.0, © Commonwealth of Australia |
| ABS, ASGS Edition 3 (2021) SA1 and Mesh Block boundaries | Areas, residential land share, boundary change flags | CC BY 4.0, © Commonwealth of Australia |
| OpenStreetMap via the Overpass API | Naming the road, railway, water or park along each cliff | ODbL, © OpenStreetMap contributors |
| CARTO basemap (map pages only) | Background map in the 3D renders | © CARTO, © OpenStreetMap contributors |
| Microburbs API (© Microburbs; automated, indicative estimates; City of Sydney only) | Income figures consistent with the chosen edge (consistency check, not independent confirmation) | Hackathon key, used on the day; no raw API output stored or republished |
| Microburbs supplied Task 1 files (social hooks, businesses, posts CSVs) | Analysed on the day only | Not republished and not committed, per the hackathon rules |

No supplied hackathon files, API output, licensed data rows or keys are committed. All data is
downloaded into `data/` and derived into `out/`, both ignored by git.

Every figure in the post comes from `out/cliffs_top.csv`, which is produced by `run_all.R`
from the sources above.

## How to run

Requirements: R 4.3+, Quarto 1.4+, Git. VS Code with the R and Quarto extensions is recommended.

```bash
Rscript install.R               # install packages (one-off)
Rscript tests/testthat.R        # full test suite (method, parsers, pipeline, advanced)
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
R/advanced.R      step-vs-slope transect test and 2016 side-gap change
R/post_assets.R   artefact screen, fixed-rule line selection, 1080x1920 post assets
R/streets.R       OpenStreetMap lookup of what runs along each cliff
R/microburbs.R    Microburbs API client (key from environment only)
R/maps.R          3D map page per cliff (deck.gl), for screen recording
R/pipeline.R      orchestration with resumable checkpoints
run_all.R         command-line entry point
report.qmd        source of report.html
tests/            synthetic-data tests for method, parsers, pipeline and advanced
scripts/          synthetic demo, pre-push audit and hand-off bundle builder
```

## Limits

Area-level data describes neighbourhoods, not individuals. A cliff shows where things change,
not why. Census figures are from 2021.
