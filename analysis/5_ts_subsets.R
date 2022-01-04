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
      # And(image$select('BRIGHT')$gt(0.07))$
      # And(image$select('BRIGHT')$lt(0.3))$
      # And(image$select('ILI')$gt(1.2))$
      And(image$select('MNDWI')$gt(0))$
      And(image$select('NDVI')$lte(0))
    
    image$mask(water)
  })
}

subset_a = subsets_gee$filter(ee$Filter$eq('subset', 'A'))
# subset_b = subsets_gee$filter(ee$Filter$eq('subset', 'B'))
# subset_c = subsets_gee$filter(ee$Filter$eq('subset', 'C'))

water_a = water_ext(annual_lc, subset_a)
# water_b = water_ext(annual_lc, subset_b)
# water_c = water_ext(annual_lc, subset_c)

Map$centerObject(subset_a)
Map$addLayer(annual_lc$first(), rgbVis, name = 'Complete') | 
  Map$addLayer(water_a$first(), rgbVis, name = 'Water Mask')

years_col = annual_lc$aggregate_array('year')$getInfo()
Map$addLayers(water_a, rgbVis, name = as.character(years_col), shown = F)

visParams = list(bands = 'MNDWI', palette = 'cyan')

rgbVisSetup = water_a$map(function(img) {
  do.call(img$visualize, visParams) %>% 
    ee$Image$clip(subset_a)
})

gifParams <- list(
  region = subset_a$geometry(),
  dimensions = 800,
  crs = 'EPSG:3857',
  framesPerSecond = 1
)

browseURL(rgbVisSetup$getVideoThumbURL(gifParams))

library(magick)
gif = image_read('analysis/extra/example_water_ext.gif')

years = seq(1985, 2020, 1)

gif_year = gif %>% 
  image_annotate(text = years, boxcolor = 'black', size = 30, color = 'white') 

image_write(format = 'gif', image = gif_year, path = 'analysis/extra/example_water_year.gif') 


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