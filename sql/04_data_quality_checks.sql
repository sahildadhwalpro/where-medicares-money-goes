-- =============================================================
-- 04  Data quality checks (PostgreSQL)
-- Run after 01-03. These only read data, they don't change anything.
-- Each check says what a pass looks like.
-- =============================================================


-- 1. Rows per year: raw vs clean
--    Pass: about 3,360 raw rows a year; clean has about 66 fewer
--    (territories and UNKNOWN counties removed). States = 51 x 3 age groups = 153.
SELECT
    year,
    COUNT(*)                                                   AS clean_rows,
    SUM(CASE WHEN geo_lvl = 'National' THEN 1 ELSE 0 END)      AS national_rows,
    SUM(CASE WHEN geo_lvl = 'State'    THEN 1 ELSE 0 END)      AS state_rows,
    SUM(CASE WHEN geo_lvl = 'County'   THEN 1 ELSE 0 END)      AS county_rows
FROM clean.gv
GROUP BY year
ORDER BY year;

SELECT
    year,
    COUNT(*) AS raw_rows
FROM raw.gv_raw
GROUP BY year
ORDER BY year;


-- 2. What got removed
--    Pass: only territories and UNKNOWN counties
SELECT
    bene_geo_lvl,
    CASE
        WHEN bene_geo_desc LIKE '%-UNKNOWN' THEN 'UNKNOWN county'
        ELSE 'Territory'
    END             AS reason_removed,
    COUNT(*)        AS rows_removed
FROM raw.gv_raw
WHERE (bene_geo_lvl = 'State'  AND bene_geo_desc IN ('PR', 'VI', 'Territory', 'ZZ'))
   OR (bene_geo_lvl = 'County' AND (bene_geo_desc LIKE '%-UNKNOWN' OR bene_geo_desc LIKE 'VI-%'))
GROUP BY
    bene_geo_lvl,
    reason_removed;


-- 3. Are the UNKNOWN rows worth anything?
--    Pass: every UNKNOWN row is fully suppressed ("*"), so nothing usable was lost
SELECT
    benes_om_cnt,
    tot_mdcr_pymt_amt,
    COUNT(*) AS rows
FROM raw.gv_raw
WHERE bene_geo_desc LIKE '%-UNKNOWN'
GROUP BY
    benes_om_cnt,
    tot_mdcr_pymt_amt;


-- 4. How much of each state's people are in the clean county rows
--    Pass: above 99.5% every year (the gap is UNKNOWN and suppressed rows)
SELECT
    year,
    SUM(CASE WHEN geo_lvl = 'County' THEN benes_om_cnt END)                         AS people_in_counties,
    SUM(CASE WHEN geo_lvl = 'State' AND age_lvl = 'All' THEN benes_om_cnt END)      AS people_in_states,
    ROUND(100.0 * SUM(CASE WHEN geo_lvl = 'County' THEN benes_om_cnt END)
        / SUM(CASE WHEN geo_lvl = 'State' AND age_lvl = 'All' THEN benes_om_cnt END), 2) AS pct_covered
FROM clean.gv
GROUP BY year
ORDER BY year;


-- 5. Age groups add up: under 65 + 65 and over = All
--    Pass: 0 rows
SELECT
    a.year,
    a.geo_desc,
    a.benes_om_cnt                           AS all_ages,
    young.benes_om_cnt + old.benes_om_cnt    AS sum_of_groups
FROM clean.gv AS a
JOIN clean.gv AS young
    ON young.year = a.year
   AND young.geo_desc = a.geo_desc
   AND young.geo_lvl = a.geo_lvl
   AND young.age_lvl = '<65'
JOIN clean.gv AS old
    ON old.year = a.year
   AND old.geo_desc = a.geo_desc
   AND old.geo_lvl = a.geo_lvl
   AND old.age_lvl = '>=65'
WHERE a.age_lvl = 'All'
  AND a.benes_om_cnt <> young.benes_om_cnt + old.benes_om_cnt;


-- 6. Spending categories add up to the total (national, per person)
--    Pass: the 17 categories come in a bit under the total every year.
--    The leftover is "Other Part B services" (about $170 in 2024).
SELECT
    year,
    tot_mdcr_stdzd_pymt_pc AS total,
    ip_mdcr_stdzd_pymt_pc + snf_mdcr_stdzd_pymt_pc + hh_mdcr_stdzd_pymt_pc
  + irf_mdcr_stdzd_pymt_pc + ltch_mdcr_stdzd_pymt_pc + hospc_mdcr_stdzd_pymt_pc
  + op_mdcr_stdzd_pymt_pc + asc_mdcr_stdzd_pymt_pc + op_dlys_mdcr_stdzd_pymt_pc
  + fqhc_rhc_mdcr_stdzd_pymt_pc + em_mdcr_stdzd_pymt_pc + prcdrs_mdcr_stdzd_pymt_pc
  + tests_mdcr_stdzd_pymt_pc + imgng_mdcr_stdzd_pymt_pc + trtmnts_mdcr_stdzd_pymt_pc
  + amblnc_mdcr_stdzd_pymt_pc + dme_mdcr_stdzd_pymt_pc AS sum_of_17_categories
FROM clean.gv
WHERE geo_lvl = 'National'
  AND age_lvl = 'All'
ORDER BY year;


-- 7. Avoidable-stay (PQI) columns are empty at county level
--    Pass: County = 0 filled, State and National all filled
SELECT
    geo_lvl,
    COUNT(*)                     AS rows,
    COUNT(pqi08_chf_age_ge_75)   AS heart_failure_filled
FROM clean.gv
WHERE age_lvl = 'All'
GROUP BY geo_lvl;


-- 8. Missing values in key county columns, 2024
--    Pass: only a handful, almost all in small counties
SELECT
    COUNT(*)                                                                       AS counties,
    SUM(CASE WHEN tot_mdcr_stdzd_pymt_pc IS NULL THEN 1 ELSE 0 END)                AS missing_spending,
    SUM(CASE WHEN acute_hosp_readmsn_pct IS NULL THEN 1 ELSE 0 END)                AS missing_readmissions,
    SUM(CASE WHEN acute_hosp_readmsn_pct IS NULL AND small_county = 'No' THEN 1 ELSE 0 END) AS missing_readmissions_big_counties
FROM clean.gv
WHERE geo_lvl = 'County'
  AND year = 2024;


-- 9. Small counties (under 1,000 traditional Medicare people) per year
SELECT
    year,
    COUNT(*)                                                 AS counties,
    SUM(CASE WHEN small_county = 'Yes' THEN 1 ELSE 0 END)    AS small_counties
FROM clean.gv
WHERE geo_lvl = 'County'
GROUP BY year
ORDER BY year;


-- 10. Every county has a rural-urban code
--     Pass: 0 rows
SELECT DISTINCT
    g.fips,
    g.geo_desc
FROM clean.gv AS g
LEFT JOIN clean.county_rural_urban AS r
    ON r.fips = g.fips
WHERE g.geo_lvl = 'County'
  AND r.fips IS NULL;


-- 11. Connecticut: 8 counties until 2021, 9 planning regions from 2022
SELECT
    year,
    COUNT(*) AS ct_areas
FROM clean.gv
WHERE geo_lvl = 'County'
  AND state_code = 'CT'
GROUP BY year
ORDER BY year;


-- 12. Headline check: total spending
--     Pass: about $377 billion in 2024
SELECT
    year,
    ROUND(tot_mdcr_pymt_amt / 1000000000, 1)  AS actual_spending_billions,
    benes_om_cnt,
    tot_mdcr_stdzd_pymt_pc                    AS price_adjusted_per_person
FROM clean.gv
WHERE geo_lvl = 'National'
  AND age_lvl = 'All'
  AND year IN (2014, 2024);
