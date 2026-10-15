-- =============================================================
-- 02  Rural-urban codes (PostgreSQL)
-- USDA Rural-Urban Continuum Codes: 1-3 = metro, 4-9 = rural
--
-- Why two years of codes:
-- Connecticut switched from 8 counties to 9 planning regions.
-- Medicare uses the old counties for 2014-2021 and the planning
-- regions for 2022-2024. The 2023 USDA file has the planning regions,
-- the 2013 file has the old counties. So: use 2023, fall back to 2013.
--
-- BEFORE RUNNING: save both USDA Excel files as CSV into
-- /Users/Shared/medicare/ and check the file paths below.
-- =============================================================


-- 1. Raw tables, same columns as the USDA files
DROP TABLE IF EXISTS raw.rucc_2013 CASCADE;

CREATE TABLE raw.rucc_2013 (
    fips            TEXT,
    state           TEXT,
    county_name     TEXT,
    population_2010 TEXT,
    rucc_2013       TEXT,
    description     TEXT
);

DROP TABLE IF EXISTS raw.rucc_2023 CASCADE;

CREATE TABLE raw.rucc_2023 (
    fips            TEXT,
    state           TEXT,
    county_name     TEXT,
    population_2020 TEXT,
    rucc_2023       TEXT,
    description     TEXT
);

COPY raw.rucc_2013
FROM '/Users/Shared/medicare/rural_urban_codes_2013.csv'
WITH (FORMAT csv, HEADER true);

COPY raw.rucc_2023
FROM '/Users/Shared/medicare/rural_urban_codes_2023.csv'
WITH (FORMAT csv, HEADER true);


-- 2. One row per county: 2023 code if there is one, otherwise the 2013 code
DROP TABLE IF EXISTS clean.county_rural_urban CASCADE;

CREATE TABLE clean.county_rural_urban AS
SELECT
    COALESCE(new.fips, old.fips)                    AS fips,
    COALESCE(new.rucc_2023, old.rucc_2013)::INT     AS rucc_code,
    CASE
        WHEN new.rucc_2023 IS NOT NULL THEN 2023
        ELSE 2013
    END                                             AS code_year
FROM raw.rucc_2023 AS new
FULL OUTER JOIN raw.rucc_2013 AS old
    ON new.fips = old.fips
WHERE COALESCE(new.rucc_2023, old.rucc_2013) IS NOT NULL;


-- 3. Add the groups we show on the dashboard
ALTER TABLE clean.county_rural_urban
    ADD COLUMN metro_rural       TEXT,
    ADD COLUMN rural_urban_group TEXT;

UPDATE clean.county_rural_urban
SET
    metro_rural = CASE
                      WHEN rucc_code <= 3 THEN 'Metro'
                      ELSE 'Rural'
                  END,
    rural_urban_group = CASE
                            WHEN rucc_code <= 3         THEN '1. Metro'
                            WHEN rucc_code IN (4, 6, 8) THEN '2. Rural, next to a metro'
                            ELSE                             '3. Rural, remote'
                        END;


-- 4. Quick check: counties in each group
SELECT
    rural_urban_group,
    code_year,
    COUNT(*) AS counties
FROM clean.county_rural_urban
GROUP BY
    rural_urban_group,
    code_year
ORDER BY
    rural_urban_group,
    code_year;
