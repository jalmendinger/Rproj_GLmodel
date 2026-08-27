#==========================================
# GLmodel
# 
#==========================================
# 
#----------------------------------------------------------------------                                                                                                 
# CODE SET UP
# Set working directory: done within my RProject
                                                                                                
# Load in tidyverse, for excel data entry, data manipulation, summary, and ggplotting:
library(tidyverse)
# General dplyr procedures for data wrangling (part of tidyverse): 
#  -- glimpse() to take a quick look at a data set
#  -- rename() to rename (replace) variable names
#  -- filter() the df to get the rows you want
#  -- select() the df to get the columns you want
#  -- group_by() to choose the grouping variable(s)
#  -- summarise() to get the resulting summary values of variables for those groups
# with all these steps "chained" or "piped" together with the |> or %>% operator
library(terra)          # gis raster handling and extraction
library(sf)             # gis vector polygon handling
library(here)           # creates portable paths starting from project directory
# The two CDL download packages are no longer used: the CDL is now read from a
#   local file (see "READ THE CDL RASTER" below), so nothing has to reach the
#   NASS/CropScape servers, which have been unreliable or down.
# library(FedData)      # CDL download via PRISM/NASS API
# library(CropScapeR)   # probably a better CDL handler

#-------------------------------------------------------------------------
# USER SPECIFIED DATA 
# path to selected polygon used to clip out data to be downloaded

# Set path to geopackage, relative to project working directory
# dirname() gets the name of the parent directory, if you need it. 
#   Can be nested to go up 2 directories
# If just building downward, here() is good.  here() returns the project home directory.
# here() builds path starting with project directory, inserting proper slashes
# file.path() more generally constructs paths for your platform
my_input_gpkg <- here("2.data_raw", "erieSW_hydro.gpkg")  # folder(s) & filename
# specify your layer (parcel polygon) name, within the gpkg
my_poly <- "ws_eriesw_sand"
# Local CDL raster, already clipped to the southwestern Lake Erie basin.
# It covers more ground than the Sandusky watershed, so it still has to be
#   cropped and masked below.
my_input_cdl <- here("2.data_raw", "erieSW_cdl.tif")
# geotiff to write the clipped result into; overwritten on each run
my_output_geotiff <- here("3.data_proc", "cdl_eriesw_sand.tif")
# CDL vintage of my_input_cdl.  This no longer drives a download -- it just
#   labels which year's data are in the local file (see 2025_30m_cdls.tif.vat.dbf).
my_year <- 2025

#-------------------------------------------------------------------------
# Open study area (SA) polygon layer stored in gpkg
# probably already in Conus Albers, but transform to crs=5070 just to be sure, by using pipe
# sf just identifies the object as a "simple feature" in spatial-R lingo
sf_SA <- st_read(my_input_gpkg, layer = my_poly) |> 
  st_transform(crs = 5070)
 
# plot(sf_SA)

#-------------------------------------------------------------------------
# READ THE CDL RASTER FROM A LOCAL FILE
# The NASS/CropScape servers that GetCDLData() and get_nass_cdl() call have been
#   down or unresponsive, so the CDL is read from a local geotiff instead.
# The download code is not gone, just parked: 1.Rcode/oldCode/ holds GLmodelv1.R
#   (the CropScapeR version of this script) and get_cdl_wcs.R (a direct call to
#   the CropScape web coverage service).  Pull either back in if the federal
#   servers come back up and downloading on the fly becomes worthwhile again.
# rast() only opens the file and reads its header (extent, resolution, crs,
#   category table); the cell values stay on disk until something asks for them,
#   so this is quick even for a large raster.
cdl_rast <- rast(my_input_cdl)

# What we should see: 30 m cells, one layer, and a category ("attribute") table
#   mapping the integer cell codes to crop names.
cdl_rast

#-------------------------------------------------------------------------
# CLIP THE CDL DOWN TO THE STUDY AREA
# terra works with its own vector class ("SpatVector"), not sf, so convert.
# The CDL is delivered in its own flavor of Albers, which may not be bit-for-bit
#   identical to EPSG:5070, so project the polygon onto whatever the raster uses
#   rather than assuming the two match.  Projecting the *polygon* (a handful of
#   vertices) rather than the raster avoids resampling, which would be wrong here
#   anyway: CDL values are class codes, not measurements, so they must never be
#   averaged or interpolated.
v_SA <- vect(sf_SA) |>
  project(crs(cdl_rast))

# Two steps get us down to the SA itself:
#  -- crop() trims the raster down to the SA's rectangular extent (fast, coarse)
#  -- mask() then sets every cell OUTSIDE the polygon to NA (slower, exact)
# Cropping first means mask() only has to work on the smaller raster.
# crop() snaps to the existing cell edges, so the output stays on the CDL's own
#   30 m grid -- no cells are shifted or resampled.
cdl_SA <- crop(cdl_rast, v_SA) |>
  mask(v_SA)

#-------------------------------------------------------------------------
# CONFIRM THE PROJECTION SURVIVED THE CLIP
# crop() and mask() never reproject, so cdl_SA should carry exactly the CRS the
#   source file had.  Check it rather than assume it.
cat("Source CDL crs :", crs(cdl_rast, describe = TRUE)$name, "\n")
cat("Clipped SA crs :", crs(cdl_SA,   describe = TRUE)$name, "\n")
cat("CRS unchanged by clip? ", identical(crs(cdl_rast), crs(cdl_SA)), "\n")

# Is that CRS the same coordinate system as our EPSG:5070 (NAD83 / Conus Albers)
#   polygon?  same.crs() compares the definitions themselves, so it returns TRUE
#   for two spellings of one projection even when one of them carries no EPSG code.
cat("Same CRS as EPSG:5070? ", same.crs(cdl_SA, "EPSG:5070"), "\n")
# And the full proj string, for the record:
cat("proj4:", crs(cdl_SA, proj = TRUE), "\n")

#-------------------------------------------------------------------------
# WRITE THE CLIPPED RASTER OUT
# Give up on writing a raster to a geopackage.  It seems too likely to lose data
#   in converting to byte type.  Write to a geoTiff instead.
# Arguments worth knowing:
#  -- datatype = "INT1U" stores one unsigned byte per cell.  CDL codes run 0-255,
#       so a byte holds them exactly and keeps the file small.
#  -- NAflag = 255 is the value written for the masked-out cells.  Code 255 is
#       unused in the CDL class table (its name is blank, its national histogram
#       count is 0), so borrowing it as NoData cannot collide with a real class.
#  -- gdal = "COMPRESS=..." shrinks the file; LZW is lossless, which matters
#       because these are class codes, not measurements.
#  -- overwrite = TRUE so re-running the script just replaces the old output
writeRaster(cdl_SA,
            filename  = my_output_geotiff,
            datatype  = "INT1U",
            NAflag    = 255,
            gdal      = c("COMPRESS=LZW", "TILED=YES"),
            overwrite = TRUE)

# Read the file back and confirm what actually landed on disk: the CRS, the 30 m
#   grid, and that the masked cells came back as NA rather than as some number.
cdl_check <- rast(my_output_geotiff)
cdl_check
cat("Written file crs:", crs(cdl_check, describe = TRUE)$name, "\n")
cat("Same CRS as EPSG:5070? ", same.crs(cdl_check, "EPSG:5070"), "\n")
cat("Cells masked to NA:", global(is.na(cdl_check), "sum", na.rm = TRUE)[[1]], "\n")

# plot(cdl_check)
