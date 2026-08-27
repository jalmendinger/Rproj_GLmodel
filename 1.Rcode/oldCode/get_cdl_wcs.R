#==========================================
# get_cdl_wcs.R
#
# Download USDA Cropland Data Layer (CDL) rasters straight from the CropScape
# web coverage service (WCS), without going through FedData or CropScapeR.
#
# WHY THIS EXISTS
# ---------------
# FedData::get_nass_cdl() and CropScapeR::GetCDLData() both hand the same
# CropScape server a bounding box and take whatever it sends back.  That server
# is a MapServer WCS with a hard ceiling on the size of a single response:
#
#   "msWCSGetCoverage20(): WCS server error. Raster size out of range,
#    width and height of resulting coverage must be no more than MAXSIZE=4096."
#
# Two things combine to trip that ceiling:
#
#  1. The service advertises the CDL on a 10 m grid, not the CDL's native 30 m.
#     (Send a DescribeCoverage request and look at <gml:offsetVector> -- it
#     says 10.000000.)  A GetCoverage request that does not say what resolution
#     it wants therefore gets 10 m cells, so a study area is counted three
#     times wider and three times taller than it actually needs to be.
#  2. FedData sends no resolution or scale parameter at all.  So any study area
#     bigger than about 40 km on a side (4096 cells x 10 m) is refused, even
#     though at the CDL's real 30 m that same area is well within range.
#
# The Sandusky study area is ~75 km x ~111 km: 2500 x 3703 cells at 30 m (fine),
# but 7495 x 11104 cells at 10 m (refused).  Hence the error.
#
# The fix is to ask for exactly the grid we want, using the WCS 2.0 SCALESIZE
# parameter to pin the returned number of columns and rows, and to break very
# large areas into tiles that each stay under the server's ceiling.
#
# Returns a terra SpatRaster of CDL class codes in EPSG:5070 (Conus Albers),
# covering the bounding box of the template.  Clip it to your polygon yourself
# with crop() + mask(), the same as before.
#==========================================

library(sf)
library(terra)
library(httr)

CDL_WCS_URL <- "https://nassgeodata.gmu.edu/CropScapeService/wms_cdlall"

# GRID ALIGNMENT -- the fussiest part of this, and worth getting right.
#
# The real CDL 30 m grid has its cell boundaries at EPSG:5070 coordinates that
# leave a remainder of 15 when divided by 30 (check for yourself: pull any clip
# off CropScape and look at its extent -- 1049985, 2053005, and so on).  The
# constant below is simply a point on that grid; any other point on it would do
# just as well.
#
# This matters more than it looks.  The server holds the CDL on a 10 m grid, and
# fills a 30 m request by taking every third cell.  Ask on the real CDL grid and
# each 30 m cell is exactly three 10 m cells wide, so the values that come back
# are the CDL's own, untouched.  Ask on a grid shifted even 5 m off and every
# cell straddles two CDL cells; the server still answers, but roughly 4% of
# cells -- the ones along boundaries between crops -- come back as the neighbour
# instead, and worse, WHICH ones do that changes with the window you asked for,
# so two overlapping downloads of the same ground disagree with each other.
# Snapping every request to this anchor is what makes the result reproducible
# and makes tiled downloads stitch back together seamlessly.
CDL_GRID_ANCHOR <- c(x = -2417805, y = 3321225)   # EPSG:5070 metres

#-------------------------------------------------------------------------
# cdl_years_available()
# Ask the server which years it actually serves.  Worth checking, because
# "last year" is not published until roughly February of the following year,
# and a missing year comes back as unhelpful XML rather than a clear message.
cdl_years_available <- function() {
  r <- GET(CDL_WCS_URL,
           query = list(service = "WCS", version = "2.0.1",
                        request = "GetCapabilities"),
           timeout(120))
  stop_for_status(r)
  txt <- content(r, as = "text", encoding = "UTF-8")
  # coverage ids look like "cdl_2024"; pull the 4-digit years back out
  ids <- regmatches(txt, gregexpr("cdl_[0-9]{4}", txt))[[1]]
  sort(unique(as.integer(sub("cdl_", "", ids))))
}

#-------------------------------------------------------------------------
# get_cdl_wcs()
#
#  template   sf object (or SpatVector); its bounding box defines what we get
#  year       CDL year, e.g. 2024
#  res        cell size in metres.  30 is the CDL's native resolution; ask for
#             anything coarser (60, 90, ...) and the server resamples for you,
#             which is a quick way to shrink a very large download.
#  cache_dir  where the finished GeoTIFF is parked so a re-run does not
#             re-download.  Delete the file, or set force = TRUE, to refresh.
#  label      short name for the study area, used in the cache filename
#  max_size   biggest tile side we will ask for, in cells.  The server's limit
#             is 4096; 4000 leaves a little headroom.
#  force      TRUE re-downloads even if a cached file exists
#
get_cdl_wcs <- function(template,
                        year,
                        res       = 30,
                        cache_dir = here::here("3.data_proc", "cdl_cache"),
                        label     = "study_area",
                        max_size  = 4000,
                        force     = FALSE) {

  # ---- cache check ------------------------------------------------------
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  outfile <- file.path(cache_dir, sprintf("%s_cdl_%d_%dm.tif", label, year, res))
  if (file.exists(outfile) && !force) {
    message("Using cached CDL: ", outfile)
    return(rast(outfile))
  }

  # ---- work out the grid we want ---------------------------------------
  # terra's SpatVector and sf's sf are different classes; accept either.
  if (inherits(template, "SpatVector")) template <- sf::st_as_sf(template)
  # EPSG:5070 is what the service publishes the CDL in, so the pixels come back
  # already in our CRS and no reprojection of the raster is needed later.
  bb <- sf::st_bbox(sf::st_transform(template, 5070))

  # Snap the bounding box OUTWARD onto the CDL grid (see CDL_GRID_ANCHOR above).
  # floor() on the low edge and ceiling() on the high edge guarantee we never
  # clip the study area.
  ox <- CDL_GRID_ANCHOR[["x"]]; oy <- CDL_GRID_ANCHOR[["y"]]
  xmin <- ox + floor(  (bb[["xmin"]] - ox) / res) * res
  xmax <- ox + ceiling((bb[["xmax"]] - ox) / res) * res
  ymin <- oy - ceiling((oy - bb[["ymin"]]) / res) * res
  ymax <- oy - floor(  (oy - bb[["ymax"]]) / res) * res

  ncol_total <- (xmax - xmin) / res
  nrow_total <- (ymax - ymin) / res

  # ---- split into tiles the server will accept --------------------------
  # Tile edges, in metres: step out from the low corner in strides of
  # (max_size cells), then cap the last edge at the far corner, so tiles abut
  # exactly with no gaps and no overlap.  An area already under the limit
  # yields two edges, i.e. one ordinary single request.
  x_edges <- unique(c(seq(xmin, xmax, by = max_size * res), xmax))
  y_edges <- unique(c(seq(ymin, ymax, by = max_size * res), ymax))

  n_requests <- (length(x_edges) - 1) * (length(y_edges) - 1)
  message(sprintf("CDL %d: %d x %d cells at %d m, fetching in %d request(s)...",
                  year, ncol_total, nrow_total, res, n_requests))

  # ---- fetch every tile -------------------------------------------------
  tiles <- list()
  for (i in seq_len(length(x_edges) - 1)) {
    for (j in seq_len(length(y_edges) - 1)) {
      tiles[[length(tiles) + 1]] <-
        cdl_fetch_one(year,
                      xmin = x_edges[i], xmax = x_edges[i + 1],
                      ymin = y_edges[j], ymax = y_edges[j + 1],
                      res  = res,
                      n    = length(tiles) + 1, of = n_requests)
    }
  }

  # ---- stitch the tiles back together -----------------------------------
  # sprc() bundles rasters into a collection; merge() glues them into one.
  # With a single tile there is nothing to glue, so pass it straight through.
  out <- if (length(tiles) == 1) tiles[[1]] else merge(sprc(tiles))

  # Name the band, then write the finished mosaic to the cache.  INT1U (one
  # unsigned byte) is the right storage type: CDL class codes run 0-255.
  names(out) <- paste0("cdl_", year)
  writeRaster(out, outfile, overwrite = TRUE, datatype = "INT1U",
              gdal = c("COMPRESS=DEFLATE", "ZLEVEL=9"))

  rast(outfile)
}

#-------------------------------------------------------------------------
# cdl_fetch_one()
# One GetCoverage request for one tile.  Internal helper, not meant to be
# called directly.
cdl_fetch_one <- function(year, xmin, xmax, ymin, ymax, res, n, of) {

  nc <- round((xmax - xmin) / res)
  nr <- round((ymax - ymin) / res)

  tf <- tempfile(fileext = ".tif")

  # The query, parameter by parameter:
  #  -- coverageid   which year's CDL, e.g. "cdl_2024"
  #  -- subset       the window we want, one entry per axis, in EPSG:5070 metres
  #  -- scalesize    THE FIX: how many columns and rows to return.  Without it
  #                    the server falls back on its own 10 m grid and refuses
  #                    anything over 4096 cells a side.  Pinning the counts is
  #                    what sets the effective resolution to `res`.
  #  -- format       image/tiff, which terra can open directly
  # (Repeating a name in the query list is deliberate -- WCS wants one `subset`
  #  and one `scalesize` per axis, and httr sends both copies.)
  r <- GET(CDL_WCS_URL,
           query = list(service    = "WCS",
                        version    = "2.0.1",
                        request    = "GetCoverage",
                        coverageid = paste0("cdl_", year),
                        subset     = sprintf("x(%f,%f)", xmin, xmax),
                        subset     = sprintf("y(%f,%f)", ymin, ymax),
                        scalesize  = sprintf("x(%d)", nc),
                        scalesize  = sprintf("y(%d)", nr),
                        format     = "image/tiff"),
           write_disk(tf, overwrite = TRUE),
           timeout(600))

  # A failed request still writes a file, but it holds an XML error report
  # rather than a picture.  Check the content type, and if it is XML, dig the
  # server's own message out and show it -- far more use than "download failed".
  ctype <- headers(r)$`content-type`
  if (is.null(ctype) || !grepl("tiff", ctype, fixed = TRUE)) {
    msg <- tryCatch(paste(readLines(tf, warn = FALSE), collapse = "\n"),
                    error = function(e) "(no readable response body)")
    txt <- regmatches(
      msg,
      regexpr("(?<=<ows:ExceptionText>).*?(?=</ows:ExceptionText>)",
              msg, perl = TRUE))
    stop("CropScape WCS request failed (HTTP ", status_code(r), "):\n",
         if (length(txt)) txt else msg, call. = FALSE)
  }

  message(sprintf("  tile %d of %d: %d x %d cells, %.1f MB",
                  n, of, nc, nr, file.size(tf) / 1e6))

  rast(tf)
}
