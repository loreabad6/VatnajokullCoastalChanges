## Setup ----
# Load libraries
library(sf)
library(rgee)
library(dplyr)

# Initialize rgee
ee_Initialize(drive = T)

## AOI ----
# Load AOI data and convert to GEE FeatureCollection
aoi = st_read('data/data_aoi/aoi.geojson') %>% 
  st_transform(4326)
aoi_ee = aoi %>% filter(aoi == 'discharge') %>% sf_as_ee()

## Helper functions ----
## Compute simple cloud score for Landsat data
cloudscore = function(image){
  scored = ee$Algorithms$Landsat$simpleCloudScore(image)
  image$addBands(scored$select('cloud')$multiply(-1)$rename('score'))
}

## Clip ImageCollection to AOI
clip2aoi = function(ic, geom){
  ic$map(function(image) image$clip(geom))
}

## Mask pixels with high cloud percentage
maskclouds = function(image){
  mask = image$select('score')$gte(-50)
  image$updateMask(mask)
}

## Rename Landsat bands 
band_names = c('B','G','R','NIR','SWIR1','SWIR2','Thermal','score')
renameL5 = function(image){
  image$select(
    opt_selectors = c('B1','B2','B3','B4','B5','B7','B6','score'),
    opt_names = band_names
  )$
    set('sensor','L5');
}
renameL7 = function(image){
  image$select(
    opt_selectors = c('B1','B2','B3','B4','B5','B7','B6_VCID_1','score'),
    opt_names = band_names
    )$
    set('sensor','L7');
}
renameL8 = function(image){
  image$select(
    opt_selectors = c('B2','B3','B4','B5','B6','B7','B10','score'),
    opt_names = band_names
  )$
  set('sensor','L8');
}

## Visualization ----
# Visualization settings True Color
rgbVis = list(
  bands = c('R', 'G', 'B'),
  min = 0,
  max = 0.4,
  gamma = 1.4
)

# Visualization settings False Color
fcVis = list(
  bands = c('SWIR1', 'NIR', 'G'),
  min = 0,
  max = 0.4,
  gamma = 1.9
)
## Terrain data ----
# Load terrain data and calculate products
arcticDEM = ee$Image('UMN/PGC/ArcticDEM/V3/2m_mosaic')$
  clip(aoi_ee)
arcticTerrain = ee$Terrain$products(arcticDEM) 

alosDEM = ee$Image("JAXA/ALOS/AW3D30/V2_2")$
  select("AVE_DSM")$
  clip(aoi_ee) 
alosTerrain = ee$Terrain$products(alosDEM)

## Landsat composites ----
# Load Landsat imagery
l5 = ee$ImageCollection("LANDSAT/LT05/C01/T1_TOA")$
  filterBounds(aoi_ee)$
  map(cloudscore)$map(renameL5)
l7 = ee$ImageCollection("LANDSAT/LE07/C01/T1_TOA")$
  filterBounds(aoi_ee)$
  map(cloudscore)$map(renameL7)
l8 = ee$ImageCollection("LANDSAT/LC08/C01/T1_TOA")$
  filterBounds(aoi_ee)$
  map(cloudscore)$map(renameL8)

landsatCol = l5$merge(l7)$merge(l8)$
  filter(ee$Filter$lt('CLOUD_COVER', 30))$filter(ee$Filter$neq('CLOUD_COVER', -1))

# Create yearly composites
## Define years
# Used for the complete analysis
years = seq(as.Date('1985-06-01'), as.Date('2020-06-01'), by = 'year') %>%
  as.character() %>% lapply(ee$Date) %>% ee$List()
# Used for testing  
# years = c('2015-06-01','2019-06-01') %>% lapply(ee$Date) %>% ee$List()

## Function to add spectral indexes as bands
addindex = function(image){
  img = image$select(0:6, band_names[1:7])
  ili = img$select('R')$add(img$select('SWIR2'))$
    divide(img$select('NIR')$add(img$select('SWIR1')))$
    rename('ILI')
  mndwi = img$normalizedDifference(list('G','SWIR2'))$rename('MNDWI')
  ndvi = img$normalizedDifference(list('NIR','R'))$rename('NDVI')
  swir_nir = img$select('SWIR1')$divide(img$select('NIR'))$rename('SWIR_NIR')
  
  tir = img$select('Thermal')$unitScale(240,270)$rename('tir');
  img = img$addBands(tir)
  ndci = img$normalizedDifference(list('tir','SWIR2'))$rename('NDCI')

  img$addBands(list(ili, mndwi, ndvi, swir_nir, ndci))
}

## Function to create annual composite
yearcomposite = function(year){
  
  ### Define min and max dates
  minDate = ee$Date(year)
  maxDate = minDate$advance(4, 'month')
  
  ### Filter images between june and october
  annual = landsatCol$
    filterDate(minDate, maxDate)
  
  ### Apply focal mean to Landsat 7 to remove strips when possible
  annual = ee$Algorithms$If(
    ee$Algorithms$IsEqual(annual$first()$get('sensor'), 'L7'),
    annual$map(function(image){
      filled1a = image$focal_mean(2, 'square', 'pixels', 5)
      filled1a$blend(image)$copyProperties(image)
    }),
    annual
  ) %>% ee$ImageCollection()
  
  ### Create a composite based on a percentile reducer
  perc = 30L

  annual_img = ee$Image(
    annual$
      map(maskclouds)$
      reduce(ee$Reducer$percentile(list(perc)))
  )
  
  ### Set the date as property of the image
  annual_img$set(list('year' = ee$Date(year)$get('year')))
}

## Composite imagery
annual_lc = years$
  map(ee_utils_pyfunc(yearcomposite), dropNulls = T) %>% 
  ee$ImageCollection()

### Remove NULL years
annual_lc = annual_lc$
  map(function(image) {
    image$set('count', image$bandNames()$length())
})$filter(ee$Filter$eq('count', 8))

annual_lc = annual_lc$
  map(addindex)$
  map(function(img) img$updateMask(img$select('NDCI')$gt(0.4)))
