---
title: "RMD Practice Doc"
author: "jea"
date: "2026-07-31"
output:
  html_document:
    keep_md: true    
---
I am now writing a single sentence. 

``` r
library(terra)          # raster handling and extraction
```

```
## terra 1.8.93
```

``` r
library(sf)             # vector polygon handling
```

```
## Linking to GEOS 3.13.1, GDAL 3.11.4, PROJ 9.7.0; sf_use_s2() is TRUE
```

``` r
library(FedData)        # CDL download via PRISM/NASS API
```

```
## Warning: package 'FedData' was built under R version 4.5.3
```

```
## You have loaded FedData v4.
## As of FedData v4 we have retired
## dependencies on the `sp` and `raster` packages.
## All functions in FedData v4 return `terra` (raster)
## or `sf` (vector) objects by default, and there may be
## other breaking changes.
```

