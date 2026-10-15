# How to run the SQL

PostgreSQL scripts for *Where Medicare's Money Goes* (traditional Medicare, 2014-2024).

## Setup (once)
1. Make a folder the database can read: `/Users/Shared/medicare/` (Postgres on a Mac usually can't read Desktop, Documents or Downloads).
2. Put these files in it:
   - the CMS file, renamed to `Medicare_Geographic_Variation_Public_Use_File.csv`
   - `data/raw/rural_urban_codes_2013.csv` and `data/raw/rural_urban_codes_2023.csv` from this repo (the USDA Excel files saved as CSV)
3. Create an empty folder `/Users/Shared/medicare/exports/`.
4. Create a database (for example `medicare`) and open a Query Tool on it.

## Run the scripts in order
| File | What it does |
|---|---|
| `01_load_raw.sql` | Loads the CMS file as-is: 36,994 rows, 246 text columns |
| `02_load_rural_urban.sql` | USDA rural-urban lookup (uses 2023 codes, falls back to 2013) |
| `03_clean_table.sql` | `clean.gv`: 69 typed columns, "*" and "NA" turned into NULL, territories and UNKNOWN rows removed, helper flags |
| `04_data_quality_checks.sql` | 12 read-only checks. Each one says what a pass looks like |
| `05_views_dashboard.sql` | CPI table + the 6 views the dashboard uses (schema `tableau`) |
| `06_views_extra.sql` | 11 views I explored but left off the dashboard (schema `extra`) |
| `07_export_csv.sql` | Writes one CSV per dashboard view to `/exports` |
| `08_key_findings.sql` | Recomputes every number on the dashboard, plus other ways to count the $621M |

## Dashboard views (one CSV each)
| Tab | View | Grain |
|---|---|---|
| 1, 3 | `v_national_trend` | US x year: spending, inflation-adjusted spending, hospital stays, readmission rate, Medicare Advantage share, county 10th/90th percentiles |
| 1 | `v_year_compare` | 2014, 2019 and 2024 bars: spending split into 2014 spending, inflation and real growth; Medicare Advantage share |
| 1 | `v_spending_change` | change in spending per person by type of care, 2014 to 2024 |
| 2, 3 | `v_county` | county x year: spending vs US, readmission rate vs US |
| 2 | `v_county_gap_drivers` | year x 18 types of care: share of the county gap |
| 3 | `v_readmission_estimate` | year: counties above the US rate, extra readmissions, cost |
