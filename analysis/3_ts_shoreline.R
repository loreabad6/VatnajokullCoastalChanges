## Setup ----
# Load libraries
library(sf)
library(stars)
library(rgee)
library(mapview)
library(dplyr)

# Source Image collection code
source('analysis/2_img_collection.R')

## AOI ----
# Load AOI data
aoi_sea = aoi %>% filter(aoi == 'sea') %>% 
  sf_as_ee()
aoi_shoreline = aoi %>% filter(aoi == 'shoreline')

region_sea = aoi %>% filter(aoi == 'sea') %>% 
  st_bbox() %>% st_as_sfc() %>% 
  sf_as_ee()

## Sea water extraction ----
sea_ext = function(image){
  ## Water extraction is performed through spectral index thresholding, 
  ## with a combination of the following:
  water = image$select('SWIR_NIR')$lt(0.65)$ # glacier & lakes & rivers & shadows
      And(image$select('ILI')$gt(1.2))$
      And(image$select('NDVI')$lte(0))
  
  ## This code is meant to extract only the sea water, 
  ## however, terrain data does not give promising results yet.
  sea = alosTerrain$select('slope')$focal_min(1)$unmask(0)$lt(1)$
    Or(arcticTerrain$select('slope')$focal_min(1)$unmask(0)$lt(1))
  
  ## The final results is the water layer with an MNDWI higher than 0.7.
  im = image$
    mask(water)$
    #updateMask(sea)$
    select('MNDWI')
  im$gt(0.7)$copyProperties(image)
}

## The function is mapped in the annual Landsat collection and clipped to the "sea" AOI
sea = annual_lc$map(sea_ext) %>% 
  clip2aoi(aoi_sea) 

## Sea time series analysis ----
## Sea occurrence from sum of water pixels during the 36 years of analysis. 
seaOccurrence = sea$map(function(img) img$unmask(0))$reduce(ee$Reducer$sum())

## Define epochs of analysis 
epochs = seq(1985,2020,1) %>% split(cut(.,7)) %>% lapply(ee$List)

## Get the mean water occurrence for each epoch
reduce_sea_per_epoch = function(epoch){
  sea$filter(ee$Filter$inList('year',epoch))$
    map(function(img) img$unmask(0))$
    reduce(ee$Reducer$mean())$
    set('epoch', epoch)
}

epochsMean = epochs %>% 
  lapply(reduce_sea_per_epoch) %>% 
  unname() 

epochsMeanIC = epochsMean %>% 
  ee$ImageCollection$fromImages()

## Compute changes between epochs
changeEp1Ep7 = epochsMean[[1]]$mask(epochsMean[[1]]$gt(0))$
  subtract(epochsMean[[7]]$mask(epochsMean[[7]]$gt(0)))

## Mapview
years_col = sea$aggregate_array('year')$getInfo()
# Define discrete intervals to apply to the change image.
intervals <- paste0(
  "<RasterSymbolizer>",
  '<ColorMap  type="ramp" extended="false" >',
  '<ColorMapEntry color="#32cd32" quantity="-0.5" label="New water occurrence"/>', #green
  '<ColorMapEntry color="#FFFFFF" quantity="0" label="No change" />', #white
  '<ColorMapEntry color="#8B008B" quantity="0.5" label="New land occurrence" />', #purple
  "</ColorMap>",
  "</RasterSymbolizer>"
)

Map$centerObject(aoi_sea)
Map$addLayer(
    seaOccurrence$mask(seaOccurrence$gt(3)), 
    list(bands = 'MNDWI_sum', min = 4, max = 33, palette = c('#FFFFFF', '#FFB6C1', '#8B008B')), 
    legend = T, name = 'Sea Occurrence', shown = F
  ) +
  Map$addLayer(
    changeEp1Ep7$sldStyle(intervals), 
    legend = F, name = 'Change between 1985-1990 and 2015-2020', shown = F
  ) 

Map$addLayers(
  epochsMeanIC$map(function(img) img$updateMask(img$gt(0.3))), 
  list(palette = c('#FFFFFF','#40E0D0'), min = 0.3), 
  name = names(epochs), shown = F, legend = T
)

Map$addLayers(annual_lc, name = as.character(years_col), visParams = rgbVis, shown = F, legend = T)