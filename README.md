---
title: "Readme.Biomass availability in the Pacific Northwest."
author: "Jeremy Kwok Choon"
date: "April, 1, 2026`"
output: html_document
---

# Forest Bioenergy Potential for Pacific Northwest Tribal Lands

## Overview
This project assesses sustainable forest biomass energy potential within economically viable distances of major tribal reservations in the Pacific Northwest. Using R to analyze TreeMap and LANDFIRE spatial data, I evaluated renewable energy capacity under a 40% thinning management scenario. A key takeaway is the potential to power over 510,000 homes annually, effectively bridging wildfire resilience with tribal energy sovereignty.

## Research Question
What is the sustainable forest bioenergy potential within 5 miles of major tribal reservations in the Pacific Northwest, and how does this potential vary across different harvest management scenarios?

## Key Findings
- **Study Area**: Major tribal reservations (>10,000 acres) with 5-mile resilience buffer zones
- **Management Scenario**: 40% thinning intensity applied across 20-, 30-, and 40-year rotation cycles
- **Annual Energy (Top 10 Tribes)**:
  - 20-Year Cycle: 11,000,000+ MWh/year
  - 30-Year Cycle: ~7,300,000 MWh/year
  - 40-Year Cycle: ~5,500,000 MWh/year
- **Household Equivalents (Annual)**:
  - 20-Year Cycle: ~1,000,000 homes
  - 30-Year Cycle: ~680,000 homes
  - 40-Year Cycle: ~510,000 homes
- **Top Reservations**: Yakama, Warm Springs, Cow Creek, Colville, and Quinault

## Methodology
- **Spatial Analysis**: 30-meter resolution raster analysis using TreeMap 2022 biomass data
- **Buffer Analysis**: 5-mile zones around tribal boundaries representing economic hauling distance
- **Harvest Scenarios**: Three sustainable harvest rates tested:
  - Conservative: 10% over 20 years
  - Moderate: 20% over 20 years (recommended)
  - Aggressive: 30% over 20 years
- **Energy Calculations**: Biomass converted to energy using Higher Heating Value (19.0 GJ/Mg for mixed PNW forests)

## Repository Structure

```text
Tribal_Biomass_PNW/
├── Data/                       # Raw data folder (excluded from Git)
│   └── README.md               # Data download links and instructions
├── Narrative/                  # Project Story & Presentation
│   ├── Figures/                # Maps and charts used in the story
│   └── Narrative.md            # "Powering Tribal Resilience" project story
├── Notebook/                   # R Scripts
│   ├── 01_Exploratory.R        # Analysis of Forest Structure (CBD, Height, etc.)
│   └── 02_Biomass_Analysis.R   # Main Energy & Biomass calculations
└── Output/                     # Final Results
    └── All figures             # All figures
```

## Data Sources

### Primary Datasets
- **TreeMap 2022 CONUS DRYBIO** - USDA Forest Service
  - Aboveground dry Live biomass above Ground (Tons/Acre)
  - 30 m resolution
  - [Download here](https://data.fs.usda.gov/geodata/rastergateway/treemap/)

- **LANDFIRE 2024** - USGS/USFS
  - CONUS, Canopy Height, Canopy Cover, Canopy Bulk Density, and related vegetation layers
  - 30 m resolution
  - [Download here](https://landfire.gov/data/FullExtentDownloads?field_version_target_id=All&field_theme_target_id=All&field_region_id_target_id=4)

- **USFS Continental US Forest Type** - USDA Forest Service
  - Forest type raster layer for the continental United States
  - [Download here](https://data.fs.usda.gov/geodata/rastergateway/forest_type/index.php)
  
- **US Census Tribal Tracts / Native Areas / States** - TIGER/Line 2019
  - Accessed via the `tigris` R package
  - No manual download required
    - If issues with Tribal lands
  -  - **US Census Tribal Census Tracts** - TIGER/Line 2019
  - Tribal land boundary polygons
  - [Download here](https://catalog.data.gov/dataset/tiger-line-shapefile-2019-nation-u-s-current-tribal-census-tract-national) 

### Data Not Included in Repository
Due to file size limitations, large raster datasets are not included in this repository. Please download them separately using the links above  or in Data/Readme folder.


