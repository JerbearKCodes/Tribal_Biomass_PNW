#==============================================================================
# PNW TRIBAL BIOMASS FEASIBILITY STUDY
# VERSION 3.0 - 5-MILE RESILIENCE BUFFER
# - 5-mile buffer (community resilience scale)
# - Dry biomass layer shown on buffer map
# - Harvest scenario table (20/30/40 year cycles)
#==============================================================================
install.packages("ggnewscale")
install.packages("kableExtra")  # Run once
library(kableExtra)
library(sf)
library(terra)
library(dplyr)
library(ggplot2)
library(tigris)
library(exactextractr)
library(scales)
library(tidyterra)
library(ggnewscale)

options(tigris_use_cache = TRUE)

# Master Name Cleaning Function
clean_tribe_name <- function(x) {
  x <- gsub("Tribe of |Tribe|Nation|Band|Community|of the|of|\\bThe\\b", "", x)
  x <- gsub(" Reservation| Off-Reservation Trust Land| Indian Reservation| Trust Land", "", x)
  x <- trimws(x)
  return(x)
}

#==============================================================================
# STEP 1 & 2: STATE BOUNDARIES
#==============================================================================
cat("Step 1 & 2: Loading state boundaries\n")

core_states <- c("Oregon", "Washington", "Idaho")
states <- states(cb = TRUE, year = 2019, class = "sf") %>%
  filter(NAME %in% c(core_states, "California", "Nevada", "Utah", "Wyoming", "Montana")) %>%
  st_transform(4326)
states_core <- states %>% filter(NAME %in% core_states)

#==============================================================================
# STEP 3 & 4: LOAD TRIBAL TRACTS AND FILTER TO PNW
#==============================================================================
cat("Step 3 & 4: Loading and filtering tribal tracts\n")

tribes <- st_read("PATHWAY TO tl_2019_us_ttract", quiet = TRUE)

native <- native_areas(2019) %>%
  st_drop_geometry() %>%
  select(AIANNHCE, NAMELSAD) %>%
  rename(TRIBAL_NAME = NAMELSAD)

tribes <- tribes %>%
  left_join(native, by = "AIANNHCE") %>%
  st_make_valid() %>%
  st_transform(4326)

core_union <- st_union(states_core)
tribes_core <- tribes[lengths(st_intersects(tribes, core_union)) > 0, ]

#==============================================================================
# STEP 5: DISSOLVE GEOMETRIES (PREVENT DOUBLE-COUNTING)
#==============================================================================
cat("Step 5: Dissolving overlapping geometries\n")

tribes_core <- tribes_core %>%
  mutate(TRIBE_CLEAN = clean_tribe_name(TRIBAL_NAME))

tribes_dissolved <- tribes_core %>%
  group_by(AIANNHCE, TRIBE_CLEAN) %>%
  summarise(geometry = st_union(geometry), .groups = "drop") %>%
  st_make_valid() %>%
  mutate(total_acres = as.numeric(st_area(.) / 4047))

#==============================================================================
# STEP 6: COLLECTIVE AREA BAR CHART (TOP 20)
#==============================================================================
cat("Step 6: Plotting collective land area\n")

tribes_plot_data <- tribes_dissolved %>%
  st_drop_geometry() %>%
  arrange(desc(total_acres)) %>%
  slice_head(n = 10)

ggplot(tribes_plot_data,
       aes(x = reorder(TRIBE_CLEAN, total_acres), y = total_acres)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  geom_text(aes(label = scales::comma(round(total_acres))),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma,
                     expand = expansion(mult = c(0, 0.2))) +
  labs(title = "Top 10 PNW Tribes Land Area by Reservation size",
       x = NULL, y = "Total Unique Acres") +
  theme_minimal()

#==============================================================================
# STEP 7: FILTER MAJOR TRIBES (>10,000 ACRES COLLECTIVE)
#==============================================================================
cat("Step 7: Filtering major tribes\n")

MIN_COLLECTIVE_ACRES <- 10000
tribes_major <- tribes_dissolved %>%
  filter(total_acres >= MIN_COLLECTIVE_ACRES)

cat("  Major tribes:", nrow(tribes_major), "\n")

#==============================================================================
# STEP 8: CREATE 5-MILE BUFFER
#==============================================================================
cat("Step 8: Creating 5-mile resilience buffer\n")

albers <- "+proj=aea +lat_0=23 +lon_0=-96 +lat_1=29.5 +lat_2=45.5 +datum=NAD83 +units=m"

tribes_major_proj <- st_transform(tribes_major, albers)

# 5 miles = 8,047 meters
buffer_5mi       <- st_buffer(tribes_major_proj, dist = 8047)
buffer_merged    <- st_union(buffer_5mi)
buffer_vect      <- vect(buffer_merged)

buffer_5mi_wgs84    <- st_transform(buffer_5mi, 4326)
buffer_merged_wgs84 <- st_transform(buffer_merged, 4326)
tribes_major_wgs84  <- st_transform(tribes_major, 4326)
states_core_wgs84   <- st_transform(states_core, 4326)

#==============================================================================
# MAP: Tribal Lands with 5-Mile Resilience Buffers (No Biomass Raster)
#==============================================================================
# (Optional) set a PNW-ish map window so it doesn't zoom out too far
bb <- st_as_sfc(st_bbox(c(xmin = -126, ymin = 41, xmax = -110, ymax = 50), crs = 4326))


ggplot() +
  # Core PNW states for context
  geom_sf(data = st_crop(states_core_wgs84, bb),
          fill = "grey95", color = "grey50", linewidth = 0.5) +
  # 5-mile buffers (mapped to 'fill' for legend)
  geom_sf(data = st_crop(buffer_5mi_wgs84, bb),
          aes(fill = "5-Mile Buffer"), 
          alpha = 0.15, color = "darkorange", linewidth = 0.6) +
  # Tribal lands (mapped to 'fill' for legend)
  geom_sf(data = st_crop(tribes_major_wgs84, bb),
          aes(fill = "Tribal Land"), 
          alpha = 0.7, color = "black", linewidth = 0.4) +
  # Define the manual colors for the legend
  scale_fill_manual(
    values = c("5-Mile Buffer" = "orange", "Tribal Land" = "darkgreen"),
    name = "Legend"
  ) +
  coord_sf(xlim = c(-126, -110), ylim = c(41, 50), expand = FALSE) +
  labs(
    title = "Tribal Lands in the Pacific Northwest with 5-Mile Buffers",
    subtitle = "Tribal lands > 10,000 acres",
    x = NULL, y = NULL
  ) +
  
  theme_minimal() +
  theme(
    panel.grid  = element_blank(),
    axis.text   = element_blank(),
    axis.ticks  = element_blank(),
    plot.title  = element_text(face = "bold", size = 13),
    legend.position = "bottom" # Moves the new legend to the bottom
  )

#==============================================================================
# STEP 9: LOAD BIOMASS RASTER
#==============================================================================
cat("Step 9: Loading biomass raster\n")

drybio <- rast(" LOAD DRY LIVE BIOMASS DATA TreeMap2022_CONUS_DRYBIO_L/TreeMap2022_CONUS_DRYBIO_L.tif")
crs(drybio) <- albers

# Clip to merged buffer
#drybio_clip <- crop(drybio, buffer_vect)
#drybio_clip <- mask(drybio_clip, buffer_vect)
drybio_clip <- crop(drybio, vect(states_core_wgs84) |> project(albers))

pixel_area_ha    <- prod(res(drybio_clip)) / 10000
drybio_Mg_raster <- drybio_clip * pixel_area_ha

total_biomass_Mg <- global(drybio_Mg_raster, "sum", na.rm = TRUE)[[1]]

# Energy constants
HHV        <- 19.0
MWh_per_GJ <- 0.277778
total_energy_MWh <- total_biomass_Mg * HHV * MWh_per_GJ

cat("  Total biomass (Mg):", format(round(total_biomass_Mg), big.mark = ","), "\n")
cat("  Total energy (MWh):", format(round(total_energy_MWh), big.mark = ","), "\n")

#==============================================================================
# STEP 10: BUFFER MAP WITH DRY BIOMASS LAYER
#==============================================================================
cat("Step 10: Mapping buffer with dry biomass layer\n")

# Aggregate raster for faster plotting (factor 10 = 10x coarser)
drybio_plot <- aggregate(drybio_clip, fact = 10, fun = "mean")
drybio_plot_wgs84 <- project(drybio_plot, "EPSG:4326")

# Convert to dataframe for ggplot
drybio_df <- as.data.frame(drybio_plot_wgs84, xy = TRUE, na.rm = TRUE)
names(drybio_df)[3] <- "Biomass_Mgha"

bb <- st_as_sfc(st_bbox(
  c(xmin = -126, ymin = 41, xmax = -110, ymax = 50), crs = 4326
))

ggplot() +
  # Dry biomass raster layer
  geom_tile(data = drybio_df,
            aes(x = x, y = y, fill = Biomass_Mgha)) +
  scale_fill_gradientn(
    name = "Dry Biomass\n(Mg/ha)",
    colours = c("#f7f7f7", "#d9f0a3", "#78c679", "#238443", "#005a32"),
    na.value = "transparent"
  ) +
  
  # Start new scale for the vector overlays
  ggnewscale::new_scale_fill() +
  ggnewscale::new_scale_color() +
  
  # State boundaries
  geom_sf(data = st_crop(states_core_wgs84, bb),
          fill = NA, color = "grey30", linewidth = 0.6) +
  
  # Individual 5-mile buffers (STAYS ON MAP, NO LEGEND)
  geom_sf(data = st_crop(buffer_5mi_wgs84, bb),
          fill = NA, color = "orange", linewidth = 0.4) +
  
  # Merged buffer (Mapped to fill for legend)
  geom_sf(data = st_crop(buffer_merged_wgs84, bb),
          aes(fill = "5-Mile Buffer"),
          alpha = 0.10, color = "darkorange", linewidth = 0.7) +
  
  # Tribal footprints (Mapped to color for legend)
  geom_sf(data = st_crop(tribes_major_wgs84, bb),
          aes(color = "Tribal Land (> 10,000 acres)"),
          fill = NA, linewidth = 0.7) +
  
  # Define the manual colors/fills for the legend
  scale_color_manual(
    name = "Legend",
    values = c("Tribal Land (> 10,000 acres)" = "black")
  ) +
  scale_fill_manual(
    name = "Legend",
    values = c("5-Mile Buffer" = "orange")
  ) +
  
  coord_sf(xlim = c(-126, -110), ylim = c(41, 50), expand = FALSE) +
  
  labs(
    title    = "Dry Biomass Density and Tribal Lands in PNW with 5-Mile Buffer",
    subtitle = "Tribal lands > 10,000 acres"
  ) +
  
  theme_minimal() +
  theme(
    panel.grid    = element_blank(),
    axis.title    = element_blank(), # Removes "x" and "y" titles
    axis.text     = element_blank(), # REMOVES THE DEGREE LABELS (45°N, etc.)
    axis.ticks    = element_blank(), # REMOVES THE TINY TICK MARKS
    plot.title    = element_text(face = "bold", size = 13),
    legend.position = "bottom"
  )

#==============================================================================
# STEP 11: ENERGY BY TRIBE + HOMES POWERED
#==============================================================================
cat("Step 11: Calculating energy and homes powered per tribe\n")

AVG_HOME_MWh <- 10.8  # US average household annual consumption

energy_by_tribe <- data.frame()

# UPDATED Step 11: Calculating energy for the TRIBAL LAND + 5-MILE BUFFER
cat("Step 11: Calculating energy and homes powered per tribe (including 5-mile buffer)\n")

# Ensure the buffer object has the tribe names attached
buffer_5mi_proj <- st_transform(buffer_5mi, albers)

energy_by_tribe <- data.frame()

for (i in 1:nrow(buffer_5mi_proj)) {
  tribe_name  <- buffer_5mi_proj$TRIBE_CLEAN[i]
  tribe_acres <- as.numeric(st_area(buffer_5mi_proj[i,]) / 4047) # Acres of land + buffer
  geom        <- buffer_5mi_proj[i, ] # <--- Now using the BUFFER geometry
  
  biomass_sum <- exact_extract(drybio_Mg_raster, geom, "sum")
  
  if (!is.na(biomass_sum) && biomass_sum > 0) {
    energy_MWh <- biomass_sum * HHV * MWh_per_GJ
    energy_by_tribe <- rbind(energy_by_tribe, data.frame(
      Tribe         = tribe_name,
      Area_Acres    = round(tribe_acres, 0),
      Biomass_Mg    = round(biomass_sum, 0),
      Energy_MWh    = round(energy_MWh, 0),
      Homes_Powered = round(energy_MWh / AVG_HOME_MWh, 0)
    ))
  }
}

energy_by_tribe <- energy_by_tribe %>%
  group_by(Tribe) %>%
  summarise(across(where(is.numeric), sum, na.rm = TRUE)) %>%
  arrange(desc(Energy_MWh))

cat("\n--- TRIBAL ENERGY POTENTIAL (TOP 10) ---\n")
print(head(energy_by_tribe, 10))

#==============================================================================
# STEP 12: BAR GRAPH — ENERGY POTENTIAL BY TRIBE
#==============================================================================
cat("Step 12: Bar graph of energy potential\n")

ggplot(energy_by_tribe,
       aes(x = reorder(Tribe, Energy_MWh), y = Energy_MWh)) +
  geom_bar(stat = "identity", fill = "darkgreen") +
  geom_text(aes(label = scales::comma(round(Energy_MWh))),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma,
                     expand = expansion(mult = c(0, 0.25))) +
  labs(
    title = "Tribal Biomass Energy Potential in the PNW",
    subtitle = paste("Based on Tribal land footprint with 5-mile Buffer | HHV =", HHV, "GJ/Mg"),
    x = NULL,
    y = "Total Energy Potential (MWh)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

#==============================================================================
# STEP 13: HARVEST SCENARIO TABLE (20 / 30 / 40 YEAR CYCLES)
#==============================================================================
cat("Step 13: Generating harvest scenario table\n")

# For each tribe, calculate annual energy under 3 rotation cycles
harvest_scenarios <- energy_by_tribe %>%
  select(Tribe, Energy_MWh) %>%
  mutate(
    # Annual Allowable Cut = Total Energy / Rotation Years
    Annual_MWh_20yr  = round(Energy_MWh / 20, 0),
    Annual_MWh_30yr  = round(Energy_MWh / 30, 0),
    Annual_MWh_40yr  = round(Energy_MWh / 40, 0),
    
    # Homes powered annually under each scenario
    Homes_20yr = round(Annual_MWh_20yr / AVG_HOME_MWh, 0),
    Homes_30yr = round(Annual_MWh_30yr / AVG_HOME_MWh, 0),
    Homes_40yr = round(Annual_MWh_40yr / AVG_HOME_MWh, 0)
  ) %>%
  select(Tribe,
         Annual_MWh_20yr, Homes_20yr,
         Annual_MWh_30yr, Homes_30yr,
         Annual_MWh_40yr, Homes_40yr)

cat("\n--- THEORETICAL ANNUAL HARVEST SCENARIOS ---\n")
cat("(Annual energy based on full rotation cycle)\n\n")
print(harvest_scenarios)

#==============================================================================
# TABLE: Energy Potential per Tribe (for Figures / Reporting)
#==============================================================================

energy_by_tribe %>%
  head(10) %>%
  select(Tribe, Area_Acres, Biomass_Mg, Energy_MWh, Homes_Powered) %>%
  mutate(across(where(is.numeric), ~scales::comma(.))) %>%
  kable(
    col.names = c("Tribe", "Area (Acres)", "Dry Biomass (Mg)", 
                  "Energy (MWh)", "Homes Powered"),
    align     = c("l", "r", "r", "r", "r"),
    caption   = "Top 10 PNW Tribal Biomass Energy Potential"
  ) %>%
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width        = FALSE,
    font_size         = 13
  ) %>%
  row_spec(0, bold = TRUE, background = "#238443", color = "white")

#==============================================================================
# TABLE: Harvest Scenario Results
#==============================================================================

harvest_scenarios %>%
  head(10) %>%
  mutate(across(where(is.numeric), ~scales::comma(.))) %>%
  kable(
    col.names = c(
      "Tribe",
      "Annual MWh", "Homes",
      "Annual MWh", "Homes",
      "Annual MWh", "Homes"
    ),
    align   = c("l", "r", "r", "r", "r", "r", "r"),
    caption = "Theoretical Annual Harvest Scenarios by Rotation Cycle"
  ) %>%
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width        = FALSE,
    font_size         = 13
  ) %>%
  # Bold green header
  row_spec(0, bold = TRUE, background = "#238443", color = "white") %>%
  # Group the columns under scenario headers
  add_header_above(c(
    " "          = 1,
    "20-Year Cycle" = 2,
    "30-Year Cycle" = 2,
    "40-Year Cycle" = 2
  ), bold = TRUE, background = "#005a32", color = "white")

#==============================================================================
# EXTRA: THINNING SCENARIOS (FUEL REDUCTION) - 20 / 30 / 40 YEAR ROTATIONS
#==============================================================================

cat("\nExtra: Thinning-based scenarios (fuel reduction)\n")

# Thinning intensity: 40% of standing biomass removed per cycle
THIN_INTENSITY <- 0.40

thinning_scenarios <- energy_by_tribe %>%
  select(Tribe, Energy_MWh) %>%
  mutate(
    # 20-Year Thinning Cycle
    Annual_MWh_Thin20 = round((Energy_MWh * THIN_INTENSITY) / 20, 0),
    Homes_Thin20      = round(Annual_MWh_Thin20 / AVG_HOME_MWh, 0),
    
    # 30-Year Thinning Cycle
    Annual_MWh_Thin30 = round((Energy_MWh * THIN_INTENSITY) / 30, 0),
    Homes_Thin30      = round(Annual_MWh_Thin30 / AVG_HOME_MWh, 0),
    
    # 40-Year Thinning Cycle
    Annual_MWh_Thin40 = round((Energy_MWh * THIN_INTENSITY) / 40, 0),
    Homes_Thin40      = round(Annual_MWh_Thin40 / AVG_HOME_MWh, 0)
  )

cat("\n--- THINNING SCENARIOS (TOP 10) ---\n")
print(head(thinning_scenarios, 10))

#------------------------------------------------------------------------------
# GRAPH: Annual Energy by Tribe across all 3 Thinning Rotations
#------------------------------------------------------------------------------

thinning_long <- thinning_scenarios %>%
  select(Tribe, Annual_MWh_Thin20, Annual_MWh_Thin30, Annual_MWh_Thin40) %>%
  tidyr::pivot_longer(
    cols      = starts_with("Annual_MWh"),
    names_to  = "Scenario",
    values_to = "Annual_MWh"
  ) %>%
  mutate(
    Scenario = dplyr::recode(
      Scenario,
      "Annual_MWh_Thin20" = "20-Year Thinning Cycle",
      "Annual_MWh_Thin30" = "30-Year Thinning Cycle",
      "Annual_MWh_Thin40" = "40-Year Thinning Cycle"
    )
  )

top10_tribes <- thinning_scenarios %>%
  arrange(desc(Annual_MWh_Thin20)) %>%
  head(10) %>%
  pull(Tribe)

# Filter thinning_long to only those 10 tribes
ggplot(thinning_long %>% filter(Tribe %in% top10_tribes),
       aes(x = reorder(Tribe, Annual_MWh),
           y = Annual_MWh, fill = Scenario)) +
  geom_col(position = "dodge") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma,
                     expand = expansion(mult = c(0, 0.2))) +
  scale_fill_manual(values = c(
    "20-Year Thinning Cycle" = "#fdbb84",
    "30-Year Thinning Cycle" = "#e08214",
    "40-Year Thinning Cycle" = "#8c510a"
  )) +
  labs(
    title    = "Top 10 Tribes: Annual Biomass Energy by 40% Thinning Rotation",
    subtitle = paste0(
      "Tribal land + 5-mile buffer | ",
      THIN_INTENSITY * 100, "% thinning intensity applied to 20, 30, and 40-year cycles"
    ),
    x    = NULL,
    y    = "Annual Energy (MWh)",
    fill = NULL
  ) +
  theme_minimal() +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    panel.grid.minor = element_blank(),
    legend.position  = "bottom"
  )


#------------------------------------------------------------------------------
# TABLE: Thinning Scenarios across 20 / 30 / 40 Year Rotations (Top 10)
#------------------------------------------------------------------------------

thinning_scenarios %>%
  arrange(desc(Annual_MWh_Thin20)) %>%
  head(10) %>%
  select(Tribe,
         Annual_MWh_Thin20, Homes_Thin20,
         Annual_MWh_Thin30, Homes_Thin30,
         Annual_MWh_Thin40, Homes_Thin40) %>%
  mutate(across(where(is.numeric), ~ scales::comma(.))) %>%
  kable(
    col.names = c(
      "Tribe",
      "Annual MWh", "Homes",
      "Annual MWh", "Homes",
      "Annual MWh", "Homes"
    ),
    align   = c("l", "r", "r", "r", "r", "r", "r"),
    caption = paste0(
      "Thinning Harvest Scenarios (40% Intensity) by Rotation Cycle ",
      "— Tribal Land + 5-Mile Buffer"
    )
  ) %>%
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width        = FALSE,
    font_size         = 13
  ) %>%
  row_spec(0, bold = TRUE, background = "#238443", color = "white") %>%
  add_header_above(c(
    " "                    = 1,
    "20-Year Thinning Cycle" = 2,
    "30-Year Thinning Cycle" = 2,
    "40-Year Thinning Cycle" = 2
  ), bold = TRUE, background = "#005a32", color = "white")
#==============================================================================
# STEP 14: SAVE ALL OUTPUTS
#==============================================================================
cat("\nStep 14: Saving outputs\n")

write.csv(energy_by_tribe,    "tribal_energy_potential.csv",    row.names = FALSE)
write.csv(harvest_scenarios,  "harvest_scenarios.csv",          row.names = FALSE)

cat("\n=== ANALYSIS COMPLETE ===\n")
cat("Outputs saved:\n")
cat("  tribal_energy_potential.csv\n")
cat("  harvest_scenarios.csv\n")