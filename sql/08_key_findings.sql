-- =============================================================
-- 08  Key findings (PostgreSQL)
-- Every number on the dashboard, recomputed from the views.
-- If a number on the dashboard looks off, check it here.
-- =============================================================


-- -------------------------------------------------------------
-- Finding 1: Spending went up 37%, but only about 3% after inflation
-- -------------------------------------------------------------

-- Expect: $9,191 (2014) -> $12,553 (2024) = +36.6%
--         inflation +32.5%, so $9,474 in 2014 dollars = +3.1%
SELECT
    year,
    price_adjusted_per_person,
    per_person_2014_dollars,
    growth_since_2014,
    inflation_since_2014,
    growth_after_inflation,
    actual_spending_billions
FROM tableau.v_national_trend
WHERE year IN (2014, 2024);

-- Expect: of the $3,363 increase by 2024, $2,987 is inflation (89%) and $375 is real growth (11%).
--         In 2019, real growth was $479, more than in 2024: all the real growth
--         happened before COVID, and since then inflation drove the increase.
SELECT
    year_label,
    piece,
    value
FROM tableau.v_year_compare
WHERE measure = 'Spending per person'
ORDER BY
    year_label,
    sort_order;

-- Same thing in 2014 dollars. Expect: $9,191 (2014), $9,634 (2019), $9,474 (2024)
SELECT
    year,
    per_person_2014_dollars
FROM tableau.v_national_trend
WHERE year IN (2014, 2019, 2024);

-- Expect: Medicare Advantage share 32% (2014), 41% (2019), 55% (2024)
SELECT
    year_label,
    value AS ma_share
FROM tableau.v_year_compare
WHERE measure = 'Medicare Advantage share'
  AND piece = 'Medicare Advantage'
ORDER BY year_label;

-- Expect: the extra $3,363 went mostly to outpatient (+$1,249) and doctor and clinic (+$1,147).
--         Hospital stays +$258 only. The 6 changes add up to $3,363.
SELECT
    care_group,
    per_person_2014,
    per_person_2024,
    change_per_person
FROM tableau.v_spending_change
ORDER BY change_per_person DESC;

-- Expect: hospital stays per 1,000 people 282 -> 225
--         Medicare Advantage share 32% -> 55%
SELECT
    year,
    hospital_stays_per_1000,
    ma_share
FROM tableau.v_national_trend
WHERE year IN (2014, 2024);


-- -------------------------------------------------------------
-- Finding 2: Counties differ a lot, and post-acute care is the biggest piece
-- -------------------------------------------------------------

-- Expect: 10th percentile county $10,148, 90th percentile $14,398 (2,592 counties)
SELECT
    county_p10_per_person,
    county_p90_per_person,
    county_p90_per_person - county_p10_per_person AS gap,
    counties_1000_plus
FROM tableau.v_national_trend
WHERE year = 2024;

-- Expect: post-acute care 36%, doctor and clinic 25%, hospital stays 19%
SELECT
    care_group,
    SUM(share_of_gap) AS share_of_gap
FROM tableau.v_county_gap_drivers
WHERE year = 2024
GROUP BY care_group
ORDER BY share_of_gap DESC;

-- Check: the 18 pieces add up to 100%
SELECT
    year,
    SUM(share_of_gap) AS should_be_1
FROM tableau.v_county_gap_drivers
GROUP BY year
ORDER BY year;

-- Check: post-acute share in every year (expect 36% to 43%)
SELECT
    year,
    SUM(share_of_gap) AS post_acute_share
FROM tableau.v_county_gap_drivers
WHERE care_group = 'Post-acute care'
GROUP BY year
ORDER BY year;


-- -------------------------------------------------------------
-- Finding 3: Readmissions above the national rate cost about $621M a year
-- -------------------------------------------------------------

-- Expect: readmission rate about 18% every year, 2014-2024
SELECT
    year,
    readmission_rate
FROM tableau.v_national_trend
ORDER BY year;

-- Expect 2024: 878 counties, 48,499 extra readmissions, $12,804 per stay, $621M
SELECT
    year,
    us_readmission_rate,
    counties_above_us,
    extra_readmissions,
    cost_per_stay,
    cost_millions
FROM tableau.v_readmission_estimate
WHERE year = 2024;

-- Expect: counties range from 13.6% (10th percentile) to 20.2% (90th percentile)
SELECT
    PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY readmission_rate) AS county_p10,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY readmission_rate) AS county_median,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY readmission_rate) AS county_p90
FROM tableau.v_county
WHERE year = 2024
  AND small_county = 'No';


-- Other ways to count the $621M (2024)

-- a) Include counties under 1,000 people. Expect about $631M
SELECT
    ROUND(SUM(c.acute_hosp_readmsn_cnt / c.acute_hosp_readmsn_pct
        * (c.acute_hosp_readmsn_pct - n.acute_hosp_readmsn_pct))
        * n.ip_mdcr_stdzd_pymt_pc / (n.ip_cvrd_stays_per_1000_benes / 1000)
        / 1000000)                                                AS cost_millions
FROM clean.gv AS c
JOIN clean.gv AS n
    ON n.year = c.year
   AND n.geo_lvl = 'National'
   AND n.age_lvl = 'All'
WHERE c.geo_lvl = 'County'
  AND c.year = 2024
  AND c.acute_hosp_readmsn_pct > n.acute_hosp_readmsn_pct
GROUP BY
    n.ip_mdcr_stdzd_pymt_pc,
    n.ip_cvrd_stays_per_1000_benes;

-- b) Use the actual cost per hospital stay instead of the price-adjusted one.
--    Expect about $16,933 per stay and $821M
SELECT
    ROUND(n.ip_mdcr_pymt_pc / (n.ip_cvrd_stays_per_1000_benes / 1000)) AS actual_cost_per_stay,
    ROUND(e.extra_readmissions
        * n.ip_mdcr_pymt_pc / (n.ip_cvrd_stays_per_1000_benes / 1000)
        / 1000000)                                                AS cost_millions
FROM tableau.v_readmission_estimate AS e
JOIN clean.gv AS n
    ON n.year = e.year
   AND n.geo_lvl = 'National'
   AND n.age_lvl = 'All'
WHERE e.year = 2024;

-- c) Compare counties to the median county instead of the US rate. Expect about $1.1B
SELECT
    ROUND(SUM(c.acute_hosp_readmsn_cnt / c.acute_hosp_readmsn_pct
        * (c.acute_hosp_readmsn_pct - m.median_rate))
        * n.ip_mdcr_stdzd_pymt_pc / (n.ip_cvrd_stays_per_1000_benes / 1000)
        / 1000000)                                                AS cost_millions
FROM clean.gv AS c
JOIN clean.gv AS n
    ON n.year = c.year
   AND n.geo_lvl = 'National'
   AND n.age_lvl = 'All'
JOIN (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY acute_hosp_readmsn_pct) AS median_rate
    FROM clean.gv
    WHERE geo_lvl = 'County'
      AND year = 2024
      AND small_county = 'No'
) AS m
    ON TRUE
WHERE c.geo_lvl = 'County'
  AND c.year = 2024
  AND c.small_county = 'No'
  AND c.acute_hosp_readmsn_pct > m.median_rate
GROUP BY
    n.ip_mdcr_stdzd_pymt_pc,
    n.ip_cvrd_stays_per_1000_benes;

-- Where the extra readmissions are (2024, counties with 1,000+ people above the US rate)
-- Expect: CA about 6,060, FL 5,560, IL 4,370 at the top. All states add up to 48,499.
SELECT
    c.state_code,
    COUNT(*)                                                       AS counties_above_us,
    ROUND(SUM(c.readmissions / c.readmission_rate
        * (c.readmission_rate - c.us_readmission_rate)))           AS extra_readmissions
FROM tableau.v_county AS c
WHERE c.year = 2024
  AND c.small_county = 'No'
  AND c.readmission_rate > c.us_readmission_rate
GROUP BY c.state_code
ORDER BY extra_readmissions DESC;

-- Expect: the top 10 states hold about 70% of the extra readmissions,
--         and the top 100 counties (of 878) hold about 68%
SELECT
    ROUND(SUM(extra_readmissions) / 48499.0, 3) AS share_top_100_counties
FROM (
    SELECT
        readmissions / readmission_rate * (readmission_rate - us_readmission_rate) AS extra_readmissions
    FROM tableau.v_county
    WHERE year = 2024
      AND small_county = 'No'
      AND readmission_rate > us_readmission_rate
    ORDER BY extra_readmissions DESC
    LIMIT 100
) AS top_counties;
