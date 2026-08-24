# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An R analysis project (not a package) modeling how land conversions affect nutrient loads and
biodiversity in the Great Lakes watershed. Funded by a Great Lakes Protection Fund grant to the
Freshwater Society (Minnesota). Work is exploratory and script-driven — there is no build, no
test suite, and no package namespace.

## Layout and path conventions

Directories are numbered variants of the standard R-package layout (see `README.md`):

- `1.Rcode/` — R scripts (`GLmodel.R` is the main analysis script)
- `2.data_raw/` — raw inputs; **gitignored**, contains a large geopackage (`erieSW_hydro.gpkg`, ~150 MB)
- `3.data_proc/` — processed intermediates
- `4.results/` — plots, reports, outputs
- `tmp/` — scratch / practice files, not part of the analysis

Because directory names start with digits, they are not valid R identifiers — always quote them.
Build paths with `here::here("2.data_raw", "file.gpkg")`, never with `setwd()` or absolute paths;
the working directory is set by the RStudio project (`Rproj_GLmodel.Rproj`).

## Running the code

Open `Rproj_GLmodel.Rproj` in RStudio and source `1.Rcode/GLmodel.R`, or from a shell:

```sh
Rscript 1.Rcode/GLmodel.R
```

Key packages: `tidyverse`, `sf` (vector), `terra` (raster), `CropScapeR` (USDA CDL download),
`here` (paths). `FedData` was tried for CDL and abandoned — it is commented out; don't reintroduce
it without reason.

## Analysis pipeline (current state)

1. Read the study-area polygon layer (`my_poly <- "ws_eriesw_sand"`) from the geopackage with
   `st_read()` and `st_transform(crs = 5070)` (CONUS Albers — the project's standard CRS; keep
   rasters and vectors in it).
2. Download Cropland Data Layer rasters for the study-area bounding box via
   `CropScapeR::GetCDLData(aoi = sf_SA, year = my_year, type = 'b')`. `my_year` defaults to
   last calendar year.
3. `crop()` + `mask()` the CDL raster to the study-area polygon and write it to
   `3.data_proc/output.gpkg` as raster layer `cdlSA`.
4. Downstream land-conversion modeling is not yet written.

`GetCDLData()` returns a legacy `raster::RasterLayer`, not a `SpatRaster` — wrap it in
`terra::rast()` before using terra verbs on it.

Writing rasters into a geopackage has two traps, both handled in `GLmodel.R` and worth preserving:
byte datatypes are stored as RGBA picture tiles (use `datatype = "FLT4S"` to keep one band and
keep masked cells as NA), and writing a `RASTER_TABLE` name that already exists fails, so the
file is deleted and rebuilt. `sf::st_layers()` does not list raster layers — inspect with
`terra::rast()` / `terra::describe()`.

User-tunable inputs are gathered in the `USER SPECIFIED DATA` block near the top of `GLmodel.R`;
add new configurables there rather than scattering them through the script.

## CropScapeR server calls

`GetCDLData()` calls against `nassgeodata.gmu.edu` hung or timed out for a stretch (see commit
4416acb and `.Rhistory`) even though the server was up. A machine reboot cleared it; the SSL
workaround tried at the time (`httr::set_config(config(ssl_verifypeer = FALSE))`) was not the fix
and is not needed. If it recurs, suspect the local network/session state rather than the R logic.

## Style

The author writes heavily commented, teaching-style code: block header banners (`#====`, `#----`),
inline notes explaining what each function does and why. Match that density when editing
`1.Rcode/`; prefer the native pipe `|>`.
