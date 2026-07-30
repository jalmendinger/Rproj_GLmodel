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
library(FedData)        # CDL download via PRISM/NASS API

#-------------------------------------------------------------------------
# USER SPECIFIED DATA 
# path to selected polygon used to clip out data to be downloaded
#   all relative to working directory of R project

# Set path to geopackage, specific to my file structure, relative to working directory
# dirname() gets the name of the parent directory. I need to go 2 dirs up from my R project working dir
my_gpkg <- paste0(dirname(dirname(getwd())), "/3.gis/erieSW/hydro/erieSW_hydro.gpkg")

# open study area (SA) polygon layer stored in gpkg
# probably already in Conus Albers, but transform to crs=5070 just to be sure, by using pipe
sf_SA <- st_read(my_gpkg, layer = "ws_eriesw_sand") %>% st_transform(crs = 5070)


