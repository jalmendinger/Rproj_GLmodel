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
library(terra)          # raster handling and extraction
library(sf)             # vector polygon handling
# library(FedData)        # CDL download via PRISM/NASS API
library(CropScapeR)     # probably a better CDL handler
library(here)           # creates portable paths starting from project directory

#-------------------------------------------------------------------------
# USER SPECIFIED DATA 
# path to selected polygon used to clip out data to be downloaded

# Set path to geopackage, specific to my file structure, relative to working directory
# dirname() gets the name of the parent directory, if you need it. 
#   Can be nested to go up 2 directories
# If just building downward, here() is good.  here() returns the project home directory.
# here() builds path starting with project directory, inserting proper slashes
# file.path() more generally constructs paths for your platform
my_gpkg <- here("2.data_raw", "erieSW_hydro.gpkg")
# specify your layer (parcel polygon) name
my_poly <- "ws_eriesw_sand"
# assume most recent CDL data are from last year
my_year <- as.integer(format(Sys.Date(), "%Y")) - 1
# otherwise specify CDL year here and uncomment the line:
# my_year <- 2025

#-------------------------------------------------------------------------
# Open study area (SA) polygon layer stored in gpkg
# probably already in Conus Albers, but transform to crs=5070 just to be sure, by using pipe
# sf just identifies the object as a "simple feature" in spatial-R lingo
sf_SA <- st_read(my_gpkg, layer = my_poly) |> 
  st_transform(crs = 5070)
 
# plot(sf_SA)

# Extract CDL data from web for bounding box around your area of interest (aoi), 
#   which is your study area (SA)
# If you get no response from the server, run the following code to repair SSL certificate
library(httr)
set_config(config(ssl_verifypeer = FALSE))

cdl_raw <- GetCDLData(aoi = sf_SA, year = my_year, type = 'b', tol_time = 30)
