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

Key packages: `tidyverse`, `sf` (vector), `terra` (raster), `httr` (CDL download), `here` (paths).
Both CDL packages have been dropped — see "CDL downloads" below. `FedData` and `CropScapeR` remain
commented out in `GLmodel.R`; don't reintroduce either without reading that section first.

## Analysis pipeline (current state)

1. Read the study-area polygon layer (`my_poly <- "ws_eriesw_sand"`) from the geopackage with
   `st_read()` and `st_transform(crs = 5070)` (CONUS Albers — the project's standard CRS; keep
   rasters and vectors in it).
2. Download Cropland Data Layer rasters for the study-area bounding box via
   `get_cdl_wcs(template = sf_SA, year = my_year, res = my_cdl_res, label = my_label)`, defined in
   `1.Rcode/get_cdl_wcs.R`. `my_year` defaults to last calendar year; `cdl_years_available()`
   reports what the server actually has. Downloads are cached under `3.data_proc/cdl_cache/`.
3. `crop()` + `mask()` the CDL raster to the study-area polygon, then write it twice: as
   `3.data_proc/cdlSA.tif` (the copy to read back for analysis) and into `3.data_proc/output.gpkg`
   as raster layer `cdlSA` (the single-file copy).
4. Downstream land-conversion modeling is not yet written.

User-tunable inputs are gathered in the `USER SPECIFIED DATA` block near the top of `GLmodel.R`;
add new configurables there rather than scattering them through the script.

## CDL downloads

`get_cdl_wcs()` talks to the CropScape web coverage service directly rather than through a package.
The full reasoning is in the header comment of `1.Rcode/get_cdl_wcs.R`; the short version:

- `FedData::get_nass_cdl()` sends no resolution parameter, so the server works at its advertised
  10 m grid and refuses anything over 4096 cells a side (`msWCSGetCoverage20(): ... Raster size
  out of range ... MAXSIZE=4096`). The study area is 2500 × 3703 cells at the CDL's real 30 m —
  fine — but 7495 × 11104 at 10 m. The fix is the WCS `SCALESIZE` parameter, which pins the
  returned column and row counts and so pins the effective resolution.
- `CropScapeR::GetCDLData()` uses a different CropScape endpoint that repeatedly hung or timed out
  (commit 4416acb, `.Rhistory`) even though the server was up. A reboot cleared it; the SSL
  workaround tried at the time (`httr::set_config(config(ssl_verifypeer = FALSE))`) was not the fix
  and is not needed. If it recurs, suspect local network/session state rather than the R logic.

**Grid alignment is not optional.** The real CDL 30 m grid has cell boundaries at EPSG:5070
coordinates ≡ 15 (mod 30); `CDL_GRID_ANCHOR` sits on that grid and every request is snapped to it.
Requests off that grid still succeed, but ~4% of cells come back as a neighbouring class, and which
ones changes with the request window, so tiles stop agreeing where they meet. Measured on the
Sandusky area: anchored correctly, a 4-tile download matched a single-request download on all
9,257,500 cells, and matched an authoritative CropScape REST clip everywhere that clip had data.

## Writing rasters to the geopackage

Three traps, all handled in `GLmodel.R`:

- Byte datatypes are stored as RGBA picture tiles, so `datatype = "FLT4S"` is used to keep one band.
- **A geopackage raster band carries no NoData value at all** — `describe()` shows no NoData entry,
  and neither `NAflag=` nor `gdal = "NODATA_VALUE=..."` puts one there. Masked cells therefore come
  back as a mix of `NA` and `0`. Recoverable, because CDL code 0 is "Background" and never a real
  class, so read the geopackage copy back as `rast(my_output_gpkg) |> subst(0, NA)`. This is why
  `cdlSA.tif` exists — it round-trips the mask exactly (verified: 3,972,583 cells masked, 3,972,583
  `NA` on read), and is the copy to use for analysis.
- Writing a `RASTER_TABLE` name that already exists fails, so the file is deleted and rebuilt.

`sf::st_layers()` does not list raster layers — inspect with `terra::rast()` / `terra::describe()`.

## Style

The author writes heavily commented, teaching-style code: block header banners (`#====`, `#----`),
inline notes explaining what each function does and why. Match that density when editing
`1.Rcode/`; prefer the native pipe `|>`.
Review the Skills in .claude/skills for style guidance. 
