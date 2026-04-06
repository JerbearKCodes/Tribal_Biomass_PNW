#==============================================================================
# PACIFIC NORTHWEST TRIBAL BIOENERGY POTENTIAL ANALYSIS
#==============================================================================
# Author: Jeremy Kwok Choon
# Purpose: Assess forest bioenergy potential for tribal lands in OR/WA/ID
# Date: [5 April 2026]
#==============================================================================

#==============================================================================
# SECTION 0: SETUP & PACKAGE INSTALLATIONf
#==============================================================================

cat("\n=== INSTALLING & LOADING PACKAGES ===\n")

# Install packages (run once, then comment out)
# install.packages(c(
#   "sf", "terra", "exactextractr", "tmap", "ggplot2", 
#   "dplyr", "readr", "rmapshaper", "leaflet", "tigris", "tidyterra"
# ))

# Load libraries
library(sf)           # Vector spatial data
library(terra)        # Raster data
library(exactextractr)# Raster-polygon intersections
library(tmap)         # Mapping
library(ggplot2)      # Plotting
library(dplyr)        # Data wrangling
library(readr)        # Read CSVs
library(tigris)       # Census boundaries
library(tidyterra)    # Terra + tidyverse integration

# Configure tigris to cache data locally
options(tigris_use_cache = TRUE)

cat("✓ All packages loaded successfully\n")

#==============================================================================
# SECTION 1: DEFINE STUDY AREA & LOAD ADMINISTRATIVE BOUNDARIES
#==============================================================================

cat("\n=== SECTION 1: STUDY AREA DEFINITION ===\n")

# Define state groups
core_states_names    <- c("Oregon", "Washington", "Idaho")
surround_states_names <- c("California", "Nevada", "Utah", "Wyoming", "Montana")
all_states_names     <- c(core_states_names, surround_states_names)

# Download state boundaries from Census TIGER/Line
cat("Loading state boundaries...\n")
states_all <- tigris::states(cb = TRUE, year = 2019, class = "sf") %>%
  filter(NAME %in% all_states_names) %>%
  st_transform(4326)  # WGS84 (lat/lon)

states_core <- states_all %>%
  filter(NAME %in% core_states_names)

cat("  ✓ Loaded", nrow(states_all), "states (all)\n")
cat("  ✓ Loaded", nrow(states_core), "states (core PNW)\n")

# Load tribal boundaries
cat("Loading tribal boundaries...\n")
tribes <- st_read("INSERT CORRECT PATHWAY /tl_2019_us_ttract", quiet = TRUE)

# Fix CRS if missing
if (is.na(st_crs(tribes))) {
  warning("Tribes shapefile missing CRS. Assuming EPSG:4326.")
  tribes <- st_set_crs(tribes, 4326)
}

# Clean and transform
tribes <- tribes %>%
  st_make_valid() %>%
  st_transform(4326)

# Filter to PNW tribes only
core_union <- st_union(states_core)
tribes_core <- tribes[lengths(st_intersects(tribes, core_union)) > 0, ]

cat("  ✓ Loaded", nrow(tribes_core), "tribal tracts in OR/WA/ID\n")

#==============================================================================
# SECTION 2: CREATE 20-MILE BUFFER ZONE
#==============================================================================

cat("\n=== SECTION 2: BUFFER ZONE CREATION ===\n")

# Project to Albers Equal Area (meters) for accurate buffering
tribes_core_proj <- st_transform(tribes_core, 5070)

# Create 20-mile (32,187 meter) buffer around each tribe
buffer_20mi_individual <- st_buffer(tribes_core_proj, dist = 32187)

# Merge overlapping buffers into single polygon
buffer_20mi_merged <- st_union(buffer_20mi_individual)

# Transform back to WGS84 for mapping
buffer_20mi_merged <- st_transform(buffer_20mi_merged, 4326)

cat("  ✓ Created merged 20-mile buffer zone\n")

#==============================================================================
# SECTION 3: VISUALIZATION - STUDY AREA MAP
#==============================================================================

cat("\n=== SECTION 3: STUDY AREA VISUALIZATION ===\n")

# Define map extent
bb_zoom_sfc <- st_as_sfc(st_bbox(
  c(xmin = -126, ymin = 35, xmax = -102, ymax = 51),
  crs = 4326
))

# Crop layers to map extent
states_all_z  <- st_crop(states_all, bb_zoom_sfc)
states_core_z <- st_crop(states_core, bb_zoom_sfc)
tribes_core_z <- st_crop(tribes_core, bb_zoom_sfc)

# Create study area map
cat("Creating study area map...\n")

p_study_area <- ggplot() +
  # Surrounding states (grey)
  geom_sf(data = states_all_z, fill = NA, color = "grey55", linewidth = 0.6) +
  
  # Core states (black outline)
  geom_sf(data = states_core_z, fill = NA, color = "black", linewidth = 0.8) +
  
  # 20-mile buffer zone (orange)
  geom_sf(data = buffer_20mi_merged, fill = "orange", alpha = 0.3, 
          color = "darkorange", linewidth = 0.8) +
  
  # Tribal lands (blue)
  geom_sf(data = tribes_core_z, fill = "dodgerblue", alpha = 0.6, 
          color = "blue", linewidth = 0.5) +
  
  # Set extent
  coord_sf(xlim = c(-126, -105), ylim = c(35, 50), expand = FALSE) +
  
  # Labels
  labs(
    title = "Study Area: 20-Mile Buffer Zone Around Tribal Lands",
    subtitle = "Oregon, Washington, Idaho",
    caption = "Data: U.S. Census Bureau TIGER/Line (2019)"
  ) +
  theme_minimal() +
  theme(
    panel.grid = element_blank(),
    axis.title = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "grey30")
  )

print(p_study_area)

# Save map
ggsave("study_area_map.png", p_study_area, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: study_area_map.png\n")

#==============================================================================
# SECTION 4: LOAD & PROCESS LANDFIRE RASTER DATA
#==============================================================================

cat("\n=== SECTION 4: LANDFIRE DATA PROCESSING ===\n")

# Define Albers Equal Area projection (LANDFIRE standard)
albers_crs <- "+proj=aea +lat_0=23 +lon_0=-96 +lat_1=29.5 +lat_2=45.5 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs"

# Transform states to Albers for raster operations
states_albers <- st_transform(states_all, albers_crs)
pnw_core <- states_albers[states_albers$NAME %in% core_states_names, ]

#------------------------------------------------------------------------------
# 4.1: Canopy Bulk Density (CBD)
#------------------------------------------------------------------------------

cat("\n--- Loading Canopy Bulk Density (CBD) ---\n")

cbd <- rast(" INSERT CORRECT PATHWAY /LF2024_CBD_250_CONUS/Tif/LC24_CBD_250.tif")
crs(cbd) <- albers_crs

# Extract PNW region
cbd_pnw <- crop(cbd, pnw_core)
cbd_pnw <- mask(cbd_pnw, pnw_core)

# Downsample for visualization (300m resolution)
cbd_pnw_agg <- aggregate(cbd_pnw, fact = 10, fun = "mean")

cat("  ✓ CBD loaded and cropped to PNW\n")
cat("  ✓ Original resolution: 30m | Display resolution: 300m\n")

#------------------------------------------------------------------------------
# 4.2: Canopy Cover (CC)
#------------------------------------------------------------------------------

cat("\n--- Loading Canopy Cover (CC) ---\n")

cc <- rast(" INSERT CORRECT PATHWAY /Landfire_Data_2024/RAW/LF2024_CC_250_CONUS/Tif/LC24_CC_250.tif")
crs(cc) <- albers_crs

# Extract PNW region
cc_pnw <- crop(cc, pnw_core)
cc_pnw <- mask(cc_pnw, pnw_core)

# Downsample for visualization
cc_pnw_agg <- aggregate(cc_pnw, fact = 10, fun = "mean")

cat("  ✓ CC loaded and cropped to PNW\n")

#------------------------------------------------------------------------------
# 4.3: Canopy Height (CH)
#------------------------------------------------------------------------------

cat("\n--- Loading Canopy Height (CH) ---\n")

ch <- rast("INSERT CORRECT PATHWAY /Landfire_Data_2024/RAW/LF2024_CH_250_CONUS/Tif/LC24_CH_250.tif")
crs(ch) <- albers_crs

# Extract PNW region
ch_pnw <- crop(ch, pnw_core)
ch_pnw <- mask(ch_pnw, pnw_core)

# Convert from decimeters to meters
ch_pnw <- ch_pnw / 10

# Downsample for visualization
ch_pnw_agg <- aggregate(ch_pnw, fact = 10, fun = "mean")

cat("  ✓ CH loaded, cropped, and converted to meters\n")

#------------------------------------------------------------------------------
# 4.4: Forest Type (EVT)
#------------------------------------------------------------------------------

cat("\n--- Loading Forest Type ---\n")

foresttype <- rast("/INSERT CORRECT PATHWAY/conus_forest-type/conus_foresttype.img")
crs(foresttype) <- albers_crs

# Extract PNW region
foresttype_pnw <- crop(foresttype, pnw_core)
foresttype_pnw <- mask(foresttype_pnw, pnw_core)

# Downsample for visualization (use modal for categorical data)
foresttype_pnw_agg <- aggregate(foresttype_pnw, fact = 10, fun = "modal")

# Check unique forest types
unique_types <- unique(values(foresttype_pnw, na.rm = TRUE))
cat("  ✓ Forest Type loaded\n")
cat("  ✓ Number of unique forest types:", length(unique_types), "\n")

#------------------------------------------------------------------------------
# 4.5: Dry Biomass (TreeMap 2022)
#------------------------------------------------------------------------------

cat("\n--- Loading Dry Biomass (TreeMap 2022) ---\n")

drybio <- rast("INSERT CORRECT PATHWAY /TreeMap2022_CONUS_DRYBIO_L/TreeMap2022_CONUS_DRYBIO_L.tif")
crs(drybio) <- albers_crs

# Extract PNW region
drybio_pnw <- crop(drybio, pnw_core)
drybio_pnw <- mask(drybio_pnw, pnw_core)

# Downsample for visualization
drybio_pnw_agg <- aggregate(drybio_pnw, fact = 10, fun = "mean")

cat("  ✓ Dry Biomass loaded and cropped to PNW\n")
cat("  ✓ Units: Mg/ha (megagrams per hectare)\n")

#==============================================================================
# SECTION 5: CONTEXTUAL VISUALIZATIONS FOR PAPER
#==============================================================================

cat("\n=== SECTION 5: CREATING CONTEXTUAL MAPS ===\n")

#------------------------------------------------------------------------------
# 5.1: Canopy Bulk Density Map
#------------------------------------------------------------------------------

cat("Creating CBD map...\n")

cbd_df <- as.data.frame(cbd_pnw_agg, xy = TRUE, na.rm = TRUE)
names(cbd_df)[3] <- "CBD"

p_cbd <- ggplot() +
  geom_raster(data = cbd_df, aes(x = x, y = y, fill = CBD)) +
  geom_sf(data = pnw_core, fill = NA, color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    name = "CBD\n(kg/m³ × 100)", 
    na.value = "transparent",
    option = "magma"
  ) +
  coord_sf(crs = albers_crs) +
  labs(
    title = "Canopy Bulk Density - Pacific Northwest",
    subtitle = "Oregon, Washington, Idaho (300m resolution)",
    caption = "Data: LANDFIRE 2024",
    x = NULL, y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14)
  )

print(p_cbd)
ggsave("map_cbd_pnw.png", p_cbd, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: map_cbd_pnw.png\n")

#------------------------------------------------------------------------------
# 5.2: Canopy Cover Map
#------------------------------------------------------------------------------

cat("Creating Canopy Cover map...\n")

cc_df <- as.data.frame(cc_pnw_agg, xy = TRUE, na.rm = TRUE)
names(cc_df)[3] <- "CC"

p_cc <- ggplot() +
  geom_tile(data = cc_df, aes(x = x, y = y, fill = CC)) +
  geom_sf(data = pnw_core, fill = NA, color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    name = "Canopy\nCover (%)", 
    na.value = "transparent",
    option = "viridis"
  ) +
  coord_sf(crs = albers_crs, datum = albers_crs) +
  labs(
    title = "Canopy Cover - Pacific Northwest",
    subtitle = "Oregon, Washington, Idaho (300m resolution)",
    caption = "Data: LANDFIRE 2024",
    x = NULL, y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14)
  )

print(p_cc)
ggsave("map_cc_pnw.png", p_cc, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: map_cc_pnw.png\n")

#------------------------------------------------------------------------------
# 5.3: Canopy Height Map
#------------------------------------------------------------------------------

cat("Creating Canopy Height map...\n")

ch_df <- as.data.frame(ch_pnw_agg, xy = TRUE, na.rm = TRUE)
names(ch_df)[3] <- "CH"

p_ch <- ggplot() +
  geom_tile(data = ch_df, aes(x = x, y = y, fill = CH)) +
  geom_sf(data = pnw_core, fill = NA, color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    name = "Canopy\nHeight (m)", 
    na.value = "transparent",
    option = "plasma",
    limits = c(0, 50)
  ) +
  coord_sf(crs = albers_crs, datum = albers_crs) +
  labs(
    title = "Canopy Height - Pacific Northwest",
    subtitle = "Oregon, Washington, Idaho (300m resolution)",
    caption = "Data: LANDFIRE 2024",
    x = NULL, y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14)
  )

print(p_ch)
ggsave("map_ch_pnw.png", p_ch, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: map_ch_pnw.png\n")

#------------------------------------------------------------------------------
# 5.4: Forest Type Map
#------------------------------------------------------------------------------

cat("Creating Forest Type map...\n")

foresttype_df <- as.data.frame(foresttype_pnw_agg, xy = TRUE, na.rm = TRUE)
names(foresttype_df)[3] <- "ForestType"

p_foresttype <- ggplot() +
  geom_tile(data = foresttype_df, aes(x = x, y = y, fill = as.factor(ForestType))) +
  geom_sf(data = pnw_core, fill = NA, color = "white", linewidth = 0.5) +
  scale_fill_viridis_d(
    name = "Forest Type", 
    na.value = "transparent",
    option = "turbo",
    guide = guide_legend(ncol = 1, keyheight = 0.4, keywidth = 0.4)
  ) +
  coord_sf(crs = albers_crs, datum = albers_crs) +
  labs(
    title = "Forest Type - Pacific Northwest",
    subtitle = "Oregon, Washington, Idaho (300m resolution)",
    caption = "Data: LANDFIRE Forest Type",
    x = NULL, y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 6),
    legend.title = element_text(size = 8)
  )

print(p_foresttype)
ggsave("map_foresttype_pnw.png", p_foresttype, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: map_foresttype_pnw.png\n")

# Forest type frequency analysis
type_freq <- as.data.frame(table(foresttype_df$ForestType))
names(type_freq) <- c("Code", "Pixels")
type_freq$Percentage <- round(type_freq$Pixels / sum(type_freq$Pixels) * 100, 2)
type_freq <- type_freq %>% arrange(desc(Pixels))

cat("\n--- Forest Type Distribution ---\n")
print(head(type_freq, 10))

#------------------------------------------------------------------------------
# 5.5: Dry Biomass Map
#------------------------------------------------------------------------------

cat("Creating Dry Biomass map...\n")

drybio_df <- as.data.frame(drybio_pnw_agg, xy = TRUE, na.rm = TRUE)
names(drybio_df)[3] <- "DRYBIO"

p_drybio <- ggplot() +
  geom_tile(data = drybio_df, aes(x = x, y = y, fill = DRYBIO)) +
  geom_sf(data = pnw_core, fill = NA, color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    name = "Dry Biomass\n(Mg/ha)", 
    na.value = "transparent",
    option = "viridis"
  ) +
  coord_sf(crs = albers_crs, datum = albers_crs) +
  labs(
    title = "Dry Biomass - Pacific Northwest",
    subtitle = "Oregon, Washington, Idaho (300m resolution)",
    caption = "Data: TreeMap 2022",
    x = NULL, y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14)
  )

print(p_drybio)
ggsave("map_drybio_pnw.png", p_drybio, width = 10, height = 8, dpi = 300)
cat("  ✓ Saved: map_drybio_pnw.png\n")

#==============================================================================
# SECTION 6: SUMMARY STATISTICS
#==============================================================================

cat("\n=== SECTION 6: SUMMARY STATISTICS ===\n")

# Biomass statistics
biomass_stats <- global(drybio_pnw, fun = c("mean", "min", "max", "sd"), na.rm = TRUE)
cat("\n--- Dry Biomass Statistics (Mg/ha) ---\n")
print(biomass_stats)

# Canopy height statistics
height_stats <- global(ch_pnw, fun = c("mean", "min", "max", "sd"), na.rm = TRUE)
cat("\n--- Canopy Height Statistics (meters) ---\n")
print(height_stats)

# Canopy cover statistics
cover_stats <- global(cc_pnw, fun = c("mean", "min", "max", "sd"), na.rm = TRUE)
cat("\n--- Canopy Cover Statistics (%) ---\n")
print(cover_stats)

cat("\n=== CONTEXTUAL ANALYSIS COMPLETE ===\n")
cat("✓ All maps saved to working directory\n")
cat("✓ Ready for bioenergy analysis\n\n")

#==============================================================================
# END OF CONTEXTUAL VISUALIZATION SECTION
#==============================================================================
# Next: Continue with your bioenergy analysis code...
#==============================================================================