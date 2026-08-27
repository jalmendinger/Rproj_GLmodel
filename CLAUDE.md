# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An R analysis project (not a package) modeling how land conversions affect nutrient loads and
biodiversity in the Great Lakes watershed. Funded by a Great Lakes Protection Fund grant to the
Freshwater Society (Minnesota). Work is exploratory and script-driven — there is no build, no
test suite, and no package namespace.

## Layout and path conventions

Directories are numbered variants of the standard R-package layout (see `README.md`):

- `1.Rcode/` — R scripts (`GLmodel.R` is the main analysis script); `1.Rcode/oldCode/` parks
  superseded scripts that are kept deliberately, not dead weight — see "CDL data source"
- `2.data_raw/` — raw inputs; **gitignored**, holds the hydrology geopackage (`erieSW_hydro.gpkg`,
  ~150 MB) and the 2025 CDL raster for the southwestern Lake Erie basin (`erieSW_cdl.tif`, ~55 MB)
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

Key packages: `tidyverse`, `sf` (vector), `terra` (raster), `here` (paths). No CDL download
package is loaded any more — see "CDL data source" below before reintroducing one.

## Analysis pipeline (current state)

1. Read the study-area polygon layer (`my_poly <- "ws_eriesw_sand"`, the Sandusky watershed) from
   the geopackage with `st_read()` and `st_transform(crs = 5070)` (CONUS Albers — the project's
   standard CRS; keep rasters and vectors in it).
2. Read the Cropland Data Layer raster from the local file `2.data_raw/erieSW_cdl.tif`
   (`my_input_cdl`) with `terra::rast()`. It covers the whole southwestern Lake Erie basin, so it
   still has to be clipped. Nothing in the pipeline touches the network.
3. `crop()` + `mask()` the CDL to the study-area polygon, then write the result to
   `3.data_proc/cdl_eriesw_sand.tif` (`my_output_geotiff`).
4. Downstream land-conversion modeling is not yet written.

User-tunable inputs are gathered in the `USER SPECIFIED DATA` block near the top of `GLmodel.R`;
add new configurables there rather than scattering them through the script.

## Clipping and writing the CDL

- **Project the polygon onto the raster, never the raster onto the polygon.** `erieSW_cdl.tif` is
  tagged `Albers_Conical_Equal_Area` with no EPSG code, but `same.crs(cdl_SA, "EPSG:5070")` is
  `TRUE` — it is the same projection as the polygon, just spelled without the code. Reprojecting
  the raster would resample it, and CDL values are class codes, not measurements: they must never
  be averaged or interpolated. `crop()`/`mask()` do not reproject, so the output keeps the source
  CRS and stays on the CDL's own 30 m grid.
- **Write a geotiff, not a geopackage** (see the appendix for why). `datatype = "INT1U"` holds the
  0–255 CDL codes in one byte; `NAflag = 255` marks the masked cells, safe because code 255 is
  unused in the CDL class table (blank name, national histogram count 0) and does not occur in the
  Sandusky clip. LZW compression is lossless, which matters for class codes.
- Verified on the current output: 2498 × 3701 cells, 3,982,455 masked to `NA`, zero value
  mismatches against a fresh re-clip of the source, class and color tables intact, 1.2 MB on disk.

## CDL data source

The pipeline reads a local file because the federal NASS/CropScape servers were down. The download
code is parked, not deleted, and should come back if those servers become dependable again:

- `1.Rcode/oldCode/get_cdl_wcs.R` — `get_cdl_wcs()`, a direct call to the CropScape web coverage
  service, plus `cdl_years_available()`. The best of the three approaches; read its header comment
  first. It cached downloads under `3.data_proc/cdl_cache/`.
- `1.Rcode/oldCode/GLmodelv1.R` — the earlier version of the main script, built on
  `CropScapeR::GetCDLData()`, with a commented `FedData::get_nass_cdl()` attempt below it.

Hard-won details, worth keeping whichever route is revived:

- `FedData::get_nass_cdl()` sends no resolution parameter, so the server works at its advertised
  10 m grid and refuses anything over 4096 cells a side (`msWCSGetCoverage20(): ... Raster size
  out of range ... MAXSIZE=4096`). The study area is 2500 × 3703 cells at the CDL's real 30 m —
  fine — but 7495 × 11104 at 10 m. The fix is the WCS `SCALESIZE` parameter, which pins the
  returned column and row counts and so pins the effective resolution.
- `CropScapeR::GetCDLData()` uses a different CropScape endpoint that repeatedly hung or timed out
  (commit 4416acb, `.Rhistory`) even though the server was up. A reboot cleared it; the SSL
  workaround tried at the time (`httr::set_config(config(ssl_verifypeer = FALSE))`) was not the fix
  and is not needed. If it recurs, suspect local network/session state rather than the R logic.
- **Grid alignment is not optional.** The real CDL 30 m grid has cell boundaries at EPSG:5070
  coordinates ≡ 15 (mod 30); `CDL_GRID_ANCHOR` sits on that grid and every request is snapped to
  it. Requests off that grid still succeed, but ~4% of cells come back as a neighbouring class, and
  which ones changes with the request window, so tiles stop agreeing where they meet. Measured on
  the Sandusky area: anchored correctly, a 4-tile download matched a single-request download on all
  9,257,500 cells, and matched an authoritative CropScape REST clip everywhere that clip had data.
  The local `erieSW_cdl.tif` is on that grid (its extent edges are ≡ 15 mod 30), so clips of it
  inherit the alignment.

## Appendix: why not a geopackage

An earlier version wrote the clipped raster into `3.data_proc/output.gpkg`. That was abandoned —
too easy to lose data on the way in. Three traps, recorded in case a geopackage is ever needed:

- Byte datatypes are stored as RGBA picture tiles, so `datatype = "FLT4S"` was needed to keep one
  band — which defeats the point of a compact class raster.
- **A geopackage raster band carries no NoData value at all** — `describe()` shows no NoData entry,
  and neither `NAflag=` nor `gdal = "NODATA_VALUE=..."` puts one there. Masked cells come back as a
  mix of `NA` and `0`. Recoverable, because CDL code 0 is "Background" and never a real class, so
  the copy had to be read back as `rast(my_output_gpkg) |> subst(0, NA)`. A geotiff round-trips the
  mask exactly and needs no such fixup.
- Writing a `RASTER_TABLE` name that already exists fails, so the file had to be deleted and
  rebuilt each run.

`sf::st_layers()` does not list raster layers — inspect with `terra::rast()` / `terra::describe()`.

## Style

The author writes heavily commented, teaching-style code: block header banners (`#====`, `#----`),
inline notes explaining what each function does and why. Match that density when editing
`1.Rcode/`; prefer the native pipe `|>`.
Review the Skills in .claude/skills for style guidance. 
