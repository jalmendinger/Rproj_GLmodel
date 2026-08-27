# Great Lakes project 
## Purpose
To model the impacts of land conversions on nutrient loads and biodiversity in the Great Lakes watershed 
## Funding
Project is funded by a grant from the Great Lakes Protection Fund to the Freshwater Society in Minnesota.  
## Directory naming conventions
Based on naming conventions for R Packages:

your_R_project/
>data/ *(Raw and processed data)*\
>R/ *(R scripts and functions)*\
>docs/ *(Documentation)*\
>outputs/ *(Results, plots, reports)*\
>readme.md *(Project description, in markdown)*\
>your_R_project.Rproj

But I renamed these folders slightly to the following:<br>

your_R_project/
>1.Rcode/ *(R scripts and functions)*\
>2.data_raw/ *(Raw data)*\
>3.data_proc/ *(Processed data)*\
>4.results/ *(Results, plots, reports)*\
>readme.md *(Project description, in markdown)*\
>your_R_project.Rproj

## Data

The raw data are **not in this repository** -- `2.data_raw/` and `3.data_proc/` are
gitignored, because the raw files are far too big for GitHub. Cloning this repo therefore
gets you the code but not the inputs, so the scripts will not run until the raw data are
back in place. Both files live in `2.data_raw/` inside this project folder, which sits in
Google Drive and syncs with it; that sync, not git, is what backs them up.

### 2.data_raw/erieSW_hydro.gpkg (~150 MB)
Hydrology of the southwestern Lake Erie basin, as a geopackage of 13 vector layers:
river flowlines (`riv_*`), surface water bodies (`swb_erieSW`), and watershed polygons
(`ws_*`) at several scales -- catchments, HUC8, HUC10, HUC12. Everything is in
EPSG:5070 (NAD83 / Conus Albers), the project's standard CRS.

The layer the analysis currently uses is **`ws_eriesw_sand`**, the Sandusky watershed:
a single polygon, HUC8 04100011, 1,169,444 acres (4,733 km2).

*Source: TODO -- these look like NHDPlus / Watershed Boundary Dataset extracts; add
where they were downloaded from and any clipping done before they landed here.*

### 2.data_raw/erieSW_cdl.tif (~55 MB)
USDA NASS Cropland Data Layer, 2025, 30 m, clipped to the southwestern Lake Erie basin
(7641 x 7142 cells). Categorical: cell values are CDL class codes carrying the class
names and the official CDL color table. Same Albers projection as the vector data.

Read from disk because the federal CropScape servers were down; see the "CDL data source"
section of `CLAUDE.md` for the download code that is parked in `1.Rcode/oldCode/`.

A stray `2025_30m_cdls.tif.vat.dbf` came along with it, which suggests this was cut from the
national `2025_30m_cdls.tif` release. That file is inert -- GDAL only reads a sidecar whose
basename matches the raster, and the class names and color table are embedded in
`erieSW_cdl.tif` itself -- so it has been parked in `2.data_raw/scratch/` rather than deleted,
in case it is useful as a plain-text record of the CDL class codes.

*Source: TODO -- add the CropScape/NASS download link and the date it was retrieved.*

## What is and is not in git

| directory | in git? | why |
| --- | --- | --- |
| `1.Rcode/` | yes | the analysis; `1.Rcode/oldCode/` parks superseded scripts on purpose |
| `2.data_raw/` | no | large, external, and unchanging -- Google Drive holds it |
| `3.data_proc/` | no | intermediates, rebuilt by re-running the script |
| `4.results/` | **yes** | figures and tables are the deliverable, and they cannot be regenerated from a clone without the raw data |
