## Setup ----
# Load libraries
library(sf)
library(stars)
library(rgee)
library(mapview)
library(dplyr)

# Source Image collection
source('analysis/2_img_collection.R')

# Source AOI subsets
source('analysis/4_aoi_subsets.R')

## AOI ----
# Convert into GEE objects
subsets_gee = sf_as_ee(subsets_bbox)

water_ext = function(ic, subset){
  ic$map(function(image){
    
    image = image$clip(subset)
    
    water = image$
      select('SWIR_NIR')$lt(0.65)$
      And(image$select('BRIGHT')$gt(0.07))$
      And(image$select('NDVI')$lte(0))
    
    image$mask(water)
  })
}

subset_a = subsets_gee$filter(ee$Filter$eq('subset', 'A'))

test = water_ext(annual_lc, subset_a)

Map$centerObject(subset_a)
Map$addLayer(annual_lc$first(), rgbVis, name = 'Complete') | 
  Map$addLayer(test$first(), rgbVis, name = 'Water Mask')

Map$addLayers(test, rgbVis, shown = F)

inspect = st_sf(
  dark_pixel = c(T, T, T, T, F),
  geometry = st_sfc(
    st_point(c(-17.19034, 63.80538)), 
    st_point(c(-17.47230, 63.78622)),
    st_point(c(-17.68481, 63.739)),
    st_point(c(-17.1821, 63.81686)),
    st_point(c(-17.50259, 63.78469)),
    crs = 4326)
  ) %>% 
  sf_as_ee()

brightness_inspect = ee_extract(test$select('BRIGHT')$first(), inspect, scale = 30, sf = T)
