-- =============================================================
-- 07  Export the dashboard CSVs (PostgreSQL)
-- One CSV per view the dashboard uses.
--
-- BEFORE RUNNING: create the folder /Users/Shared/medicare/exports/
-- (or right-click a view in pgAdmin > Import/Export Data > Export)
-- =============================================================

COPY (SELECT * FROM tableau.v_national_trend ORDER BY year)
TO '/Users/Shared/medicare/exports/national_trend.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM tableau.v_county ORDER BY year, county_fips)
TO '/Users/Shared/medicare/exports/county.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM tableau.v_county_gap_drivers ORDER BY year, sort_order)
TO '/Users/Shared/medicare/exports/county_gap_drivers.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM tableau.v_readmission_estimate ORDER BY year)
TO '/Users/Shared/medicare/exports/readmission_estimate.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM tableau.v_year_compare ORDER BY measure, year_label, sort_order)
TO '/Users/Shared/medicare/exports/year_compare.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM tableau.v_spending_change ORDER BY change_per_person DESC)
TO '/Users/Shared/medicare/exports/spending_change.csv'
WITH (FORMAT csv, HEADER true);
