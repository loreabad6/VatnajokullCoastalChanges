library(sf)
library(rgee)

# Source Image collection
source('analysis/2_img_collection.R')

glacier_ee = st_as_sf(st_sfc(st_point(c(-16.8300, 64.0212)), crs = 4326)) %>% 
  st_transform(3857) %>% 
  st_buffer(10000) %>% 
  st_transform(4326) %>% 
  sf_as_ee()


water_ext = function(ic, subset){
  ic$map(function(image){
    
    image = image$clip(subset)
    
    water = image$
      select('SWIR_NIR')$lt(0.65)$
      # And(image$select('BRIGHT')$gt(0.07))$
      # And(image$select('BRIGHT')$lt(0.3))$
      And(image$select('ILI')$gt(1.2))$
      # And(image$select('MNDWI')$gt(0))$
      And(image$select('NDVI')$lte(0))
    
    water
  })
}

rockfall_lc = annual_lc$
  filter(ee$Filter$gte('year',2012))

glacier = water_ext(rockfall_lc, glacier_ee)

years_col = rockfall_lc$aggregate_array('year')$getInfo()
Map$addLayers(glacier, list(palette = c('grey', 'blue')), name = as.character(years_col), shown = F)

visParams = list(palette = c('grey', 'blue'))

rgbVisSetup = glacier$map(function(img) {
  do.call(img$visualize, visParams) %>% 
    ee$Image$clip(glacier_ee)
})

gifParams <- list(
  region = glacier_ee$geometry(),
  dimensions = 800,
  crs = 'EPSG:3857',
  framesPerSecond = 1
)

browseURL(rgbVisSetup$getVideoThumbURL(gifParams))

## Add text to GIF
library(magick)
gif = image_read('analysis/extra/rockfall.gif')
years = seq(2012, 2020, 1)
gif_year = gif %>% 
  image_annotate(text = years, boxcolor = 'black', size = 30, color = 'white') 
image_write(format = 'gif', image = gif_year, path = 'analysis/extra/rockfall_year.gif') 
