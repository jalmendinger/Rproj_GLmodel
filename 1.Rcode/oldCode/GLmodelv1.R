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
library(FedData)        # CDL download via PRISM/NASS API
library(CropScapeR)     # probably a better CDL handler
library(here)           # creates portable paths starting from project directory

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
# geopackage to write results into; created on first write if it does not exist
my_output_geotiff <- here("3.data_proc", "cdl_eriesw_sand.tif")
# assume most recent CDL data are from last year
my_year <- as.integer(format(Sys.Date(), "%Y")) - 1
# otherwise specify CDL year here and uncomment the line:
# my_year <- 2025

#-------------------------------------------------------------------------
# Open study area (SA) polygon layer stored in gpkg
# probably already in Conus Albers, but transform to crs=5070 just to be sure, by using pipe
# sf just identifies the object as a "simple feature" in spatial-R lingo
sf_SA <- st_read(my_input_gpkg, layer = my_poly) |> 
  st_transform(crs = 5070)
 
# plot(sf_SA)

#-------------------------------------------------------------------------
# Extract CDL data using CropScapeR package
# Data are returned for bounding box around your area of interest (aoi),
#   which is your study area (SA)

cdl_raw <- GetCDLData(aoi = sf_SA, year = my_year, type = 'b', tol_time = 30)

# The download above covers the whole rectangular bounding box around the SA.
# Mask the rectangular downloaded data to your polygon.
# terra() is better for dealing with rasters.

# Two steps get us down to the SA itself:
#  -- crop() trims the raster down to the SA's rectangular extent (fast, coarse)
#  -- mask() then sets every cell OUTSIDE the polygon to NA (slower, exact)
# Cropping first means mask() only has to work on the smaller raster.

# CropScapeR still returns an old-style "RasterLayer" (from the raster package),
#   so hand it to terra, which wants a "SpatRaster"
cdl_rast <- rast(cdl_raw)

# terra works with its own vector class ("SpatVector"), not sf, so convert.
# The CDL comes back in its own flavor of Albers, which may not be bit-for-bit
#   identical to EPSG:5070, so project the polygon onto whatever the raster uses
#   rather than assuming the two match.
v_SA <- vect(sf_SA) |>
  project(crs(cdl_rast))

cdl_SA <- crop(cdl_rast, v_SA) |>
  mask(v_SA)

#-------------------------------------------------------------------------
# # Extract CDL data using FedData() package
# # sf_SA is your polygon; "SA" is just a label for caching.
# # Data are returned for the bounding box.
# cdl_rast <- get_nass_cdl(
#   template = sf_SA,
#   label    = "study_area",
#   year     = my_year
# )
# 
# # FedData returns the data as a SpatRaster, ready for terra.
# 
# # Mask the rectangular raster by your polygon.
# # Two steps get us down to the SA itself:
# #  -- crop() trims the raster down to the SA's rectangular extent (fast, coarse)
# #  -- mask() then sets every cell OUTSIDE the polygon to NA (slower, exact)
# # Cropping first means mask() only has to work on the smaller raster.
# 
# # terra works with its own vector class ("SpatVector"), not sf, so convert.
# # And, project polygon to same as the raster so they match.
# v_SA <- vect(sf_SA) |>
#   project(crs(cdl_rast))
# 
# cdl_SA <- crop(cdl_rast, v_SA) |>
#   mask(v_SA)
# 

#-------------------------------------------------------------------------
# WRITE THE CLIPPED RASTER OUT
# Give up on writing a raster to a geopackage.  It seems too likely to lose data
#   in converting to byte type.  Write to a geoTiff instead.  

# gdal options, passed through to the GPKG driver:
#  -- RASTER_TABLE names the layer inside the geopackage (like a layer name for vectors)
#  -- APPEND_SUBDATASET=YES adds a layer to the file rather than replacing the whole
#       file, so a later write of a second layer will not wipe this one out
writeRaster(cdl_SA,
            filename = my_output_gpkg,
            filetype = "GPKG",
            gdal     = c(paste0("RASTER_TABLE=", my_cdl_layer),
                         "APPEND_SUBDATASET=YES"),
            datatype = "FLT4S")

# Read it back to confirm what landed in the geopackage.
# Note st_layers() lists only VECTOR layers, so it will not show this raster;
#   use terra to look at it instead.
# rast(my_output_gpkg)
# describe(my_output_gpkg)
# 
# 