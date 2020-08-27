# Load libraries
library(sf)
library(dplyr)
library(osmdata)
library(mapview)

# Load coastline data
coastline = st_read('data/data_ref/IS_50V_STRANDLINA_170062020.gpkg', layer = 'strandlina_flakar')

# Obtain main boundary for Iceland
coastline_main = coastline %>% 
  mutate(area = st_area(.)) %>% 
  top_n(1, area) %>% 
  st_boundary

# Create buffers around coastline. 
# 30 km buffer is used for analysis of the discharge area (river network, glacier lakes, etc.), 
# i.e. the complete AOI for analysis.
coastline_buffer = coastline_main %>% 
  st_buffer(dist = 30000)
# 5 km buffer is used to analyze changes at the shoreline
coastline_sea = coastline_main %>% 
  st_buffer(dist = 5000)

# Obtain Vatnajokull polygon from OSM
# First call glacier data with {osmdata}
glaciers = opq(getbb('Iceland', featuretype = 'country')) %>% 
  add_osm_feature(key = 'natural', value = 'glacier') %>% 
  osmdata_sf() 
# Next, select multipolygons, correct encoding, extract Vatnajokull and transform to Iceland CRS
vatnajokull = glaciers$osm_multipolygons %>% 
  mutate_if(is.character, .funs = function(x){return(`Encoding<-`(x, "UTF-8"))}) %>% 
  filter(stringr::str_detect(name, 'Vatna')) %>% 
  st_transform(8088)

# Create a rotated bbox in reference to Vatnajokull to include shoreline south of the icecap
# Get bounding box
bbox = vatnajokull %>% 
  st_bbox() %>% st_as_sfc()
# Set rotating function
rotation = function(a){
  r = a * pi / 180 #degrees to radians
  matrix(c(cos(r), sin(r), -sin(r), cos(r)), nrow = 2, ncol = 2)
} 
# Rotate bounding box
rotate = (bbox - st_centroid(bbox)) * rotation(-30) + st_centroid(bbox)

# Create a 20 km buffer around it and set CRS
rotatebbox = rotate %>% 
  st_buffer(20000) %>% 
  st_set_crs(8088)

# Establish the final AOIs
aoi_shoreline = st_intersection(coastline_main, rotatebbox) %>% 
  transmute(aoi = 'shoreline')
aoi_sea = st_intersection(coastline_sea, rotatebbox) %>% 
  transmute(aoi = 'sea')
aoi_dischargenet = st_intersection(coastline_buffer, rotatebbox) %>% 
  st_convex_hull() %>% 
  transmute(aoi = 'discharge')

# Save AOIs
aoi = bind_rows(aoi_sea, aoi_dischargenet, aoi_shoreline) 
st_write(aoi, 'data/data_aoi/aoi.geojson')
