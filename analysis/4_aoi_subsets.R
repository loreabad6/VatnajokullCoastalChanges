## Setup ----
# Load libraries
library(sf)
library(stars)
library(rgee)
library(mapview)
library(dplyr)

#' Based on `3_ts_shoreline.R`, three subsequent subsets are 
#' defined according to the changes observed, see NOTES.md for details.

# Load subsets digitized in QGIS
subsets = st_read('data/data_aoi/subsets.geojson') 

# Create rectangular subsets to query in GEE, add subset name and identifier
subsets_bbox = subsets %>% 
  filter(id %in% 1:3) %>% 
  arrange(id) %>% 
  mutate(
    subset = c('A','B','C'),
    name = c('Skeiðarársandur', 'Breiðamerkursandur', 'Jökulsársandur')
  ) %>% 
  rowwise() %>% 
  mutate(geometry = st_as_sfc(st_bbox(geometry))) %>% 
  st_as_sf()
