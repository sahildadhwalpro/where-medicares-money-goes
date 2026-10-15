# Data

## raw/
- `rural_urban_codes_2013.csv`, `rural_urban_codes_2023.csv`: USDA Rural-Urban Continuum Codes, saved from the USDA Excel files as CSV.
- The CMS file is not in this repo because it's large. Download it from CMS:
  **Medicare Geographic Variation - by National, State & County** (data.cms.gov), years 2014-2024.
  Rename it to `Medicare_Geographic_Variation_Public_Use_File.csv` before running `sql/01_load_raw.sql`.

## processed/
The CSVs the Tableau dashboard uses. Each one is a view in `sql/05_views_dashboard.sql`, exported by `sql/07_export_csv.sql`.

| File | What's in it |
|---|---|
| `national_trend.csv` | US, one row per year: spending, inflation-adjusted spending, hospital stays, readmission rate, Medicare Advantage share, county 10th/90th percentiles |
| `year_compare.csv` | 2014, 2019 and 2024: spending split into 2014 spending, inflation and real growth; Medicare Advantage share |
| `spending_change.csv` | Change in spending per person by type of care, 2014 to 2024 |
| `county.csv` | One row per county and year: spending vs the US, readmission rate vs the US |
| `county_gap_drivers.csv` | Share of the county spending gap by type of care, every year |
| `readmission_estimate.csv` | Counties above the US readmission rate, extra readmissions and their cost, every year |

## Inflation
BLS CPI-U (US city average, all items, annual average), typed into `clean.cpi_u` in `sql/05_views_dashboard.sql`.
