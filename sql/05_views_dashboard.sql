-- =============================================================
-- 05  Views for the dashboard (PostgreSQL)
--
-- The dashboard answers 3 questions:
--   Tab 1  Is Medicare really getting more expensive?
--   Tab 2  Where is spending highest, and what explains the gap?
--   Tab 3  What's worth fixing?
--
-- All spending is CMS price-adjusted (standardized) $ per traditional
-- Medicare person. Price-adjusted removes local price differences
-- (wages, teaching hospitals). It does NOT remove inflation, so I
-- adjust for inflation separately with CPI-U.
-- =============================================================


-- 1. Inflation table: CPI-U, US city average, all items, annual average (1982-84 = 100)
--    Source: Bureau of Labor Statistics
DROP TABLE IF EXISTS clean.cpi_u CASCADE;

CREATE TABLE clean.cpi_u (
    year  INT PRIMARY KEY,
    cpi_u NUMERIC
);

INSERT INTO clean.cpi_u (year, cpi_u) VALUES
    (2014, 236.736),
    (2015, 237.017),
    (2016, 240.007),
    (2017, 245.120),
    (2018, 251.107),
    (2019, 255.657),
    (2020, 258.811),
    (2021, 270.970),
    (2022, 292.655),
    (2023, 304.702),
    (2024, 313.689);


-- 2. Tab 1 + Tab 3: national numbers, one row per year
--    per_person_2014_dollars = spending per person with inflation taken out
--    county_p10 / county_p90 = 10th and 90th percentile county (1,000+ people)
DROP VIEW IF EXISTS tableau.v_national_trend;

CREATE VIEW tableau.v_national_trend AS
WITH county_spread AS (
    SELECT
        year,
        COUNT(*)                                                             AS counties_1000_plus,
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY tot_mdcr_stdzd_pymt_pc) AS county_p10,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY tot_mdcr_stdzd_pymt_pc) AS county_p90
    FROM clean.gv
    WHERE geo_lvl = 'County'
      AND small_county = 'No'
      AND tot_mdcr_stdzd_pymt_pc IS NOT NULL
    GROUP BY year
)
SELECT
    n.year,
    n.covid_year,
    n.benes_om_cnt                                                          AS traditional_medicare_people,
    ROUND(n.tot_mdcr_pymt_amt / 1000000000, 1)                              AS actual_spending_billions,
    n.tot_mdcr_stdzd_pymt_pc                                                AS price_adjusted_per_person,
    ROUND(n.tot_mdcr_stdzd_pymt_pc * cpi_2014.cpi_u / cpi.cpi_u, 2)         AS per_person_2014_dollars,
    ROUND(n.tot_mdcr_stdzd_pymt_pc / base.tot_mdcr_stdzd_pymt_pc - 1, 4)    AS growth_since_2014,
    ROUND((n.tot_mdcr_stdzd_pymt_pc * cpi_2014.cpi_u / cpi.cpi_u)
        / base.tot_mdcr_stdzd_pymt_pc - 1, 4)                               AS growth_after_inflation,
    ROUND(cpi.cpi_u / cpi_2014.cpi_u - 1, 4)                                AS inflation_since_2014,
    n.ip_cvrd_stays_per_1000_benes                                          AS hospital_stays_per_1000,
    n.acute_hosp_readmsn_pct                                                AS readmission_rate,
    n.ma_prtcptn_rate                                                       AS ma_share,
    ROUND(c.county_p10::NUMERIC, 2)                                         AS county_p10_per_person,
    ROUND(c.county_p90::NUMERIC, 2)                                         AS county_p90_per_person,
    c.counties_1000_plus
FROM clean.gv AS n
JOIN clean.gv AS base
    ON base.geo_lvl = 'National'
   AND base.age_lvl = 'All'
   AND base.year = 2014
JOIN clean.cpi_u AS cpi
    ON cpi.year = n.year
JOIN clean.cpi_u AS cpi_2014
    ON cpi_2014.year = 2014
JOIN county_spread AS c
    ON c.year = n.year
WHERE n.geo_lvl = 'National'
  AND n.age_lvl = 'All';


-- 3. Tab 2 + Tab 3: one row per county and year
--    Filter small_county = 'No' in Tableau (fewer than 1,000 people is too noisy)
DROP VIEW IF EXISTS tableau.v_county;

CREATE VIEW tableau.v_county AS
SELECT
    c.year,
    c.fips                                                                  AS county_fips,
    c.state_code,
    c.county_name,
    c.geo_desc                                                              AS county_label,
    c.benes_om_cnt                                                          AS traditional_medicare_people,
    c.small_county,
    c.tot_mdcr_stdzd_pymt_pc                                                AS price_adjusted_per_person,
    us.tot_mdcr_stdzd_pymt_pc                                               AS us_price_adjusted_per_person,
    ROUND(c.tot_mdcr_stdzd_pymt_pc / us.tot_mdcr_stdzd_pymt_pc - 1, 4)      AS vs_us_average,
    c.acute_hosp_readmsn_cnt                                                AS readmissions,
    c.acute_hosp_readmsn_pct                                                AS readmission_rate,
    us.acute_hosp_readmsn_pct                                               AS us_readmission_rate,
    CASE
        WHEN c.acute_hosp_readmsn_pct > us.acute_hosp_readmsn_pct THEN 'Above US rate'
        WHEN c.acute_hosp_readmsn_pct IS NOT NULL THEN 'At or below US rate'
    END                                                                     AS readmission_vs_us
FROM clean.gv AS c
JOIN clean.gv AS us
    ON us.year = c.year
   AND us.geo_lvl = 'National'
   AND us.age_lvl = 'All'
WHERE c.geo_lvl = 'County';


-- 4. Helper view: spending in long format (one row per place, year, type of care)
--    The 17 CMS categories don't add up to the total. The leftover
--    (about $170 in 2024) is "Other Part B services", so the pieces add up.
DROP VIEW IF EXISTS clean.v_spending_long CASCADE;

CREATE VIEW clean.v_spending_long AS
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county,
       tot_mdcr_stdzd_pymt_pc AS total_per_person,
       1 AS sort_order, 'Hospital stays' AS category, 'Hospital stays' AS care_group,
       ip_mdcr_stdzd_pymt_pc AS per_person
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       2, 'Skilled nursing facility', 'Post-acute care', snf_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       3, 'Home health', 'Post-acute care', hh_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       4, 'Inpatient rehab', 'Post-acute care', irf_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       5, 'Long-term care hospital', 'Post-acute care', ltch_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       6, 'Hospice', 'Hospice', hospc_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       7, 'Hospital outpatient', 'Outpatient', op_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       8, 'Surgery centers', 'Outpatient', asc_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       9, 'Outpatient dialysis', 'Outpatient', op_dlys_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       10, 'Community clinics', 'Outpatient', fqhc_rhc_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       11, 'Doctor visits', 'Doctor and clinic', em_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       12, 'Procedures', 'Doctor and clinic', prcdrs_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       13, 'Tests', 'Doctor and clinic', tests_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       14, 'Imaging', 'Doctor and clinic', imgng_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       15, 'Treatments (clinic drugs)', 'Doctor and clinic', trtmnts_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       16, 'Ambulance', 'Doctor and clinic', amblnc_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       17, 'Medical equipment (DME)', 'Medical equipment', dme_mdcr_stdzd_pymt_pc
FROM clean.gv WHERE age_lvl = 'All'
UNION ALL
SELECT year, covid_year, geo_lvl, geo_desc, state_code, small_county, tot_mdcr_stdzd_pymt_pc,
       18, 'Other Part B services', 'Doctor and clinic',
       tot_mdcr_stdzd_pymt_pc
       - COALESCE(ip_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(snf_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(hh_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(irf_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(ltch_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(hospc_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(op_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(asc_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(op_dlys_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(fqhc_rhc_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(em_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(prcdrs_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(tests_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(imgng_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(trtmnts_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(amblnc_mdcr_stdzd_pymt_pc, 0)
       - COALESCE(dme_mdcr_stdzd_pymt_pc, 0)
FROM clean.gv WHERE age_lvl = 'All';


-- 5. Tab 2: what explains the gap between counties (counties with 1,000+ people)
--    share_of_gap = covariance(type of care, total) / variance(total)
--    It says how much of the county-to-county spread in total spending
--    comes from each type of care. All 18 add up to 100%, so they can be
--    added up by care_group (post-acute care = about 36% in 2024).
--    Suppressed values count as $0 (fewer than 11 people used that service).
DROP VIEW IF EXISTS tableau.v_county_gap_drivers;

CREATE VIEW tableau.v_county_gap_drivers AS
SELECT
    year,
    sort_order,
    category,
    care_group,
    ROUND((COVAR_POP(COALESCE(per_person, 0), total_per_person)
         / VAR_POP(total_per_person))::NUMERIC, 4)                          AS share_of_gap,
    COUNT(*)                                                                AS counties
FROM clean.v_spending_long
WHERE geo_lvl = 'County'
  AND small_county = 'No'
  AND total_per_person IS NOT NULL
GROUP BY
    year,
    sort_order,
    category,
    care_group;


-- 6. Tab 3: what readmissions above the national rate cost
--    If every county (1,000+ people) above the US readmission rate came down
--    to the US rate, how many readmissions would there be fewer of, and what
--    would those hospital stays cost?
--    hospital stays in a county = readmissions / readmission rate
--    extra readmissions         = stays x (county rate - US rate)
--    cost per hospital stay     = US hospital spending per person / hospital stays per person
--    It's a rough estimate: readmissions are all-cause (some are planned).
--    Other ways to count it are in 08_key_findings.sql.
DROP VIEW IF EXISTS tableau.v_readmission_estimate;

CREATE VIEW tableau.v_readmission_estimate AS
WITH us AS (
    SELECT
        year,
        acute_hosp_readmsn_pct                                              AS us_rate,
        ip_mdcr_stdzd_pymt_pc / (ip_cvrd_stays_per_1000_benes / 1000)       AS cost_per_stay
    FROM clean.gv
    WHERE geo_lvl = 'National'
      AND age_lvl = 'All'
),
above AS (
    SELECT
        c.year,
        c.acute_hosp_readmsn_cnt / c.acute_hosp_readmsn_pct
            * (c.acute_hosp_readmsn_pct - us.us_rate)                       AS extra_readmissions
    FROM clean.gv AS c
    JOIN us
        ON us.year = c.year
    WHERE c.geo_lvl = 'County'
      AND c.small_county = 'No'
      AND c.acute_hosp_readmsn_pct > us.us_rate
)
SELECT
    us.year,
    CASE WHEN us.year IN (2020, 2021) THEN 'Yes' ELSE 'No' END             AS covid_year,
    us.us_rate                                                              AS us_readmission_rate,
    COUNT(*)                                                                AS counties_above_us,
    ROUND(SUM(a.extra_readmissions))                                        AS extra_readmissions,
    ROUND(us.cost_per_stay)                                                 AS cost_per_stay,
    ROUND(SUM(a.extra_readmissions) * us.cost_per_stay / 1000000)           AS cost_millions
FROM above AS a
JOIN us
    ON us.year = a.year
GROUP BY
    us.year,
    us.us_rate,
    us.cost_per_stay;


-- 7. Tab 1 bar charts: 2014, 2019 and 2024
--    2019 is the last year before COVID, so it works as the midpoint
--    (2020 is distorted by COVID).
--    Spending bars are split into 3 pieces:
--      spending in 2014
--      rising prices (inflation) = 2014 spending x (CPI that year / CPI 2014 - 1)
--      real growth              = spending that year - 2014 spending - inflation
--    Medicare Advantage bars: share in Medicare Advantage vs traditional.
DROP VIEW IF EXISTS tableau.v_2014_vs_2024;
DROP VIEW IF EXISTS tableau.v_year_compare;

CREATE VIEW tableau.v_year_compare AS
SELECT
    'Spending per person'                                            AS measure,
    CAST(n.year AS TEXT)                                             AS year_label,
    1                                                                AS sort_order,
    'Spending in 2014'                                               AS piece,
    b.price_adjusted_per_person                                      AS value
FROM tableau.v_national_trend AS n
JOIN tableau.v_national_trend AS b
    ON b.year = 2014
WHERE n.year IN (2014, 2019, 2024)

UNION ALL

SELECT
    'Spending per person',
    CAST(n.year AS TEXT),
    2,
    'Rising prices (inflation)',
    ROUND(b.price_adjusted_per_person * (c.cpi_u / c14.cpi_u - 1), 2)
FROM tableau.v_national_trend AS n
JOIN tableau.v_national_trend AS b
    ON b.year = 2014
JOIN clean.cpi_u AS c
    ON c.year = n.year
JOIN clean.cpi_u AS c14
    ON c14.year = 2014
WHERE n.year IN (2019, 2024)

UNION ALL

SELECT
    'Spending per person',
    CAST(n.year AS TEXT),
    3,
    'Real growth',
    ROUND(n.price_adjusted_per_person
        - b.price_adjusted_per_person
        - b.price_adjusted_per_person * (c.cpi_u / c14.cpi_u - 1), 2)
FROM tableau.v_national_trend AS n
JOIN tableau.v_national_trend AS b
    ON b.year = 2014
JOIN clean.cpi_u AS c
    ON c.year = n.year
JOIN clean.cpi_u AS c14
    ON c14.year = 2014
WHERE n.year IN (2019, 2024)

UNION ALL

SELECT
    'Medicare Advantage share',
    CAST(year AS TEXT),
    1,
    'Medicare Advantage',
    ma_share
FROM tableau.v_national_trend
WHERE year IN (2014, 2019, 2024)

UNION ALL

SELECT
    'Medicare Advantage share',
    CAST(year AS TEXT),
    2,
    'Traditional Medicare',
    1 - ma_share
FROM tableau.v_national_trend
WHERE year IN (2014, 2019, 2024);


-- 8. Tab 1: where the extra spending went, by type of care (US, 2014 vs 2024)
--    Same $ basis as the headline: price-adjusted, not inflation-adjusted.
--    The 6 changes add up to the full $3,363 increase per person.
DROP VIEW IF EXISTS tableau.v_spending_change;

CREATE VIEW tableau.v_spending_change AS
SELECT
    care_group,
    ROUND(SUM(CASE WHEN year = 2014 THEN per_person END), 2)       AS per_person_2014,
    ROUND(SUM(CASE WHEN year = 2024 THEN per_person END), 2)       AS per_person_2024,
    ROUND(SUM(CASE WHEN year = 2024 THEN per_person END)
        - SUM(CASE WHEN year = 2014 THEN per_person END), 2)       AS change_per_person
FROM clean.v_spending_long
WHERE geo_lvl = 'National'
  AND year IN (2014, 2024)
GROUP BY care_group;
