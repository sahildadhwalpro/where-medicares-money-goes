-- =============================================================
-- 06  Extra analysis (PostgreSQL)
-- These views are NOT on the dashboard. I explored them while
-- building the project and kept them here as background.
-- They live in their own schema, "extra", so it's clear what the
-- dashboard uses (schema "tableau") and what it doesn't.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS extra;


-- 1. State cost: actual vs price-adjusted, price index
DROP VIEW IF EXISTS extra.v_state_cost;

CREATE VIEW extra.v_state_cost AS
SELECT
    s.year,
    s.covid_year,
    s.state_code,
    s.fips                                                                 AS state_fips,
    s.benes_om_cnt                                                         AS traditional_medicare_people,
    s.tot_mdcr_pymt_pc                                                     AS actual_per_person,
    s.tot_mdcr_stdzd_pymt_pc                                               AS price_adjusted_per_person,
    us.tot_mdcr_stdzd_pymt_pc                                              AS us_price_adjusted_per_person,
    ROUND(s.tot_mdcr_pymt_pc / s.tot_mdcr_stdzd_pymt_pc, 3)                AS price_index,
    -- 1.10 = 10% more care than the US average
    ROUND(s.tot_mdcr_stdzd_pymt_pc / us.tot_mdcr_stdzd_pymt_pc, 3)         AS usage_vs_us,
    -- 1.10 = prices 10% above the US average
    ROUND((s.tot_mdcr_pymt_pc / s.tot_mdcr_stdzd_pymt_pc)
        / (us.tot_mdcr_pymt_pc / us.tot_mdcr_stdzd_pymt_pc), 3)            AS prices_vs_us,
    CASE
        WHEN s.tot_mdcr_stdzd_pymt_pc >= us.tot_mdcr_stdzd_pymt_pc
         AND s.tot_mdcr_pymt_pc / s.tot_mdcr_stdzd_pymt_pc >= us.tot_mdcr_pymt_pc / us.tot_mdcr_stdzd_pymt_pc
            THEN 'More care + higher prices'
        WHEN s.tot_mdcr_stdzd_pymt_pc >= us.tot_mdcr_stdzd_pymt_pc
            THEN 'More care, lower prices'
        WHEN s.tot_mdcr_pymt_pc / s.tot_mdcr_stdzd_pymt_pc >= us.tot_mdcr_pymt_pc / us.tot_mdcr_stdzd_pymt_pc
            THEN 'Less care, higher prices'
        ELSE 'Less care + lower prices'
    END                                                                    AS cost_driver,
    base.tot_mdcr_stdzd_pymt_pc                                            AS price_adjusted_2014,
    ROUND(s.tot_mdcr_stdzd_pymt_pc / base.tot_mdcr_stdzd_pymt_pc - 1, 4)   AS growth_since_2014
FROM clean.gv AS s
JOIN clean.gv AS us
    ON us.year = s.year
   AND us.geo_lvl = 'National'
   AND us.age_lvl = 'All'
JOIN clean.gv AS base
    ON base.geo_desc = s.geo_desc
   AND base.geo_lvl = 'State'
   AND base.age_lvl = 'All'
   AND base.year = 2014
WHERE s.geo_lvl = 'State'
  AND s.age_lvl = 'All';


-- 2. Spending mix by type of care, national and by state
DROP VIEW IF EXISTS extra.v_spending_mix;

CREATE VIEW extra.v_spending_mix AS
SELECT
    s.year,
    s.covid_year,
    s.geo_lvl,
    s.state_code,
    s.sort_order,
    s.category,
    s.care_group,
    s.per_person,
    s.total_per_person,
    ROUND(s.per_person / s.total_per_person, 4)          AS share_of_total,
    base.per_person                                      AS per_person_2014,
    ROUND(s.per_person / base.per_person - 1, 4)         AS growth_since_2014
FROM clean.v_spending_long AS s
JOIN clean.v_spending_long AS base
    ON base.geo_desc = s.geo_desc
   AND base.geo_lvl = s.geo_lvl
   AND base.category = s.category
   AND base.year = 2014
WHERE s.geo_lvl IN ('National', 'State');


-- 3. How use of care lines up with county spending
--    One row per year, one column per measure
DROP VIEW IF EXISTS extra.v_use_vs_spending;

CREATE VIEW extra.v_use_vs_spending AS
SELECT
    year,
    covid_year,
    COUNT(*)                                                                         AS counties,
    ROUND(CORR(ip_cvrd_stays_per_1000_benes,  tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS hospital_stays,
    ROUND(CORR(hh_episodes_per_1000_benes,    tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS home_health,
    ROUND(CORR(snf_cvrd_stays_per_1000_benes, tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS skilled_nursing_stays,
    ROUND(CORR(benes_hospc_pct,               tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS hospice_use,
    ROUND(CORR(er_visits_per_1000_benes,      tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS er_visits,
    ROUND(CORR(acute_hosp_readmsn_pct,        tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS readmissions,
    ROUND(CORR(bene_dual_pct,                 tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS also_on_medicaid,
    ROUND(CORR(bene_avg_age,                  tot_mdcr_stdzd_pymt_pc)::NUMERIC, 3)   AS average_age
FROM clean.gv
WHERE geo_lvl = 'County'
  AND small_county = 'No'
GROUP BY
    year,
    covid_year;


-- 4. Medical equipment (DME) by state
--    Shown as an outlier worth a closer look, not as proof of fraud
DROP VIEW IF EXISTS extra.v_dme_state;

CREATE VIEW extra.v_dme_state AS
WITH state_median AS (
    SELECT
        year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dme_mdcr_stdzd_pymt_pc) AS median_dme
    FROM clean.gv
    WHERE geo_lvl = 'State'
      AND age_lvl = 'All'
    GROUP BY year
)
SELECT
    s.year,
    s.covid_year,
    s.state_code,
    s.fips                                                     AS state_fips,
    s.dme_mdcr_stdzd_pymt_pc                                   AS dme_per_person,
    ROUND(m.median_dme::NUMERIC, 2)                            AS state_median,
    ROUND(s.dme_mdcr_stdzd_pymt_pc / m.median_dme::NUMERIC, 2) AS times_state_median,
    base.dme_mdcr_stdzd_pymt_pc                                AS dme_per_person_2014
FROM clean.gv AS s
JOIN state_median AS m
    ON m.year = s.year
JOIN clean.gv AS base
    ON base.geo_desc = s.geo_desc
   AND base.geo_lvl = 'State'
   AND base.age_lvl = 'All'
   AND base.year = 2014
WHERE s.geo_lvl = 'State'
  AND s.age_lvl = 'All';


-- 5. Use of care over time
DROP VIEW IF EXISTS extra.v_utilization;

CREATE VIEW extra.v_utilization AS
SELECT
    year,
    covid_year,
    geo_lvl,
    state_code,
    ip_cvrd_stays_per_1000_benes   AS hospital_stays_per_1000,
    er_visits_per_1000_benes       AS er_visits_per_1000,
    op_visits_per_1000_benes       AS outpatient_visits_per_1000,
    snf_cvrd_stays_per_1000_benes  AS skilled_nursing_stays_per_1000,
    irf_cvrd_stays_per_1000_benes  AS rehab_stays_per_1000,
    hh_episodes_per_1000_benes     AS home_health_episodes_per_1000,  -- 2020 jump = counting change, not real growth
    benes_hospc_pct                AS hospice_use
FROM clean.gv
WHERE geo_lvl IN ('National', 'State')
  AND age_lvl = 'All';


-- 6. Readmission rate by state
DROP VIEW IF EXISTS extra.v_readmissions_state;

CREATE VIEW extra.v_readmissions_state AS
SELECT
    g.year,
    g.covid_year,
    g.geo_lvl,
    g.state_code,
    g.fips                                                        AS state_fips,
    g.acute_hosp_readmsn_cnt                                      AS readmissions,
    g.acute_hosp_readmsn_pct                                      AS readmission_rate,
    us.acute_hosp_readmsn_pct                                     AS us_readmission_rate
FROM clean.gv AS g
JOIN clean.gv AS us
    ON us.year = g.year
   AND us.geo_lvl = 'National'
   AND us.age_lvl = 'All'
WHERE g.geo_lvl IN ('National', 'State')
  AND g.age_lvl = 'All';


-- 7. Avoidable hospital stays (AHRQ PQI), per 100,000 people
--    State and US only: the county columns are empty in the CMS file.
--    I kept the 8 measures we use: every condition for ages 75+, plus COPD 65-74
DROP VIEW IF EXISTS extra.v_avoidable_stays;

CREATE VIEW extra.v_avoidable_stays AS
WITH long AS (
    SELECT year, covid_year, geo_lvl, state_code, fips, 1 AS sort_order,
           'Heart failure, 75+' AS measure, pqi08_chf_age_ge_75 AS rate_per_100k
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 2,
           'COPD/asthma, 75+', pqi05_copd_asthma_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 3,
           'COPD/asthma, 65-74', pqi05_copd_asthma_age_65_74
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 4,
           'Pneumonia, 75+', pqi11_bctrl_pna_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 5,
           'UTI, 75+', pqi12_uti_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 6,
           'Diabetes, 75+', pqi03_dbts_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 7,
           'High blood pressure, 75+', pqi07_hyprtnsn_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
    UNION ALL
    SELECT year, covid_year, geo_lvl, state_code, fips, 8,
           'Amputation, 75+', pqi16_lwrxtrmty_amputn_age_ge_75
    FROM clean.gv WHERE geo_lvl IN ('National', 'State') AND age_lvl = 'All'
)
SELECT
    l.year,
    l.covid_year,
    l.geo_lvl,
    l.state_code,
    l.fips                                                       AS state_fips,
    l.sort_order,
    l.measure,
    l.rate_per_100k,
    us.rate_per_100k                                             AS us_rate_per_100k,
    ROUND(l.rate_per_100k / us.rate_per_100k, 3)                 AS times_us_rate,
    base.rate_per_100k                                           AS rate_2014
FROM long AS l
JOIN long AS us
    ON us.year = l.year
   AND us.measure = l.measure
   AND us.geo_lvl = 'National'
JOIN long AS base
    ON base.state_code = l.state_code
   AND base.measure = l.measure
   AND base.year = 2014;


-- 8. Medicare Advantage share by state
--    ma_share = MA / (MA + traditional Medicare), same as the CMS rate.
--    medicaid_share is a share of TRADITIONAL Medicare people only.
DROP VIEW IF EXISTS extra.v_ma_state;

CREATE VIEW extra.v_ma_state AS
SELECT
    g.year,
    g.covid_year,
    g.geo_lvl,
    g.state_code,
    g.fips                                                  AS state_fips,
    g.benes_total_cnt                                       AS all_medicare_people,
    g.benes_om_cnt                                          AS traditional_medicare_people,
    g.benes_ma_cnt                                          AS medicare_advantage_people,
    g.ma_prtcptn_rate                                       AS ma_share,
    base.ma_prtcptn_rate                                    AS ma_share_2014,
    g.ma_prtcptn_rate - base.ma_prtcptn_rate                AS ma_share_change_since_2014,  -- 0.40 = +40 points
    g.bene_dual_pct                                         AS medicaid_share_in_traditional,
    base.bene_dual_pct                                      AS medicaid_share_2014
FROM clean.gv AS g
JOIN clean.gv AS base
    ON base.geo_desc = g.geo_desc
   AND base.geo_lvl = g.geo_lvl
   AND base.age_lvl = 'All'
   AND base.year = 2014
WHERE g.geo_lvl IN ('National', 'State')
  AND g.age_lvl = 'All';


-- 9. Medicare Advantage share by county
DROP VIEW IF EXISTS extra.v_ma_county;

CREATE VIEW extra.v_ma_county AS
SELECT
    c.year,
    c.covid_year,
    c.fips                                                  AS county_fips,
    c.state_code,
    c.county_name,
    c.geo_desc                                              AS county_label,
    r.rural_urban_group,
    r.metro_rural,
    c.benes_total_cnt                                       AS all_medicare_people,
    c.benes_om_cnt                                          AS traditional_medicare_people,
    c.small_county,
    c.ma_prtcptn_rate                                       AS ma_share,
    c.bene_dual_pct                                         AS medicaid_share_in_traditional
FROM clean.gv AS c
LEFT JOIN clean.county_rural_urban AS r
    ON r.fips = c.fips
WHERE c.geo_lvl = 'County';


-- 10. Under 65 vs 65 and over
DROP VIEW IF EXISTS extra.v_age_groups;

CREATE VIEW extra.v_age_groups AS
SELECT
    a.year,
    a.covid_year,
    a.geo_lvl,
    a.state_code,
    CASE
        WHEN a.age_lvl = '<65'  THEN 'Under 65 (disability)'
        WHEN a.age_lvl = '>=65' THEN '65 and over'
        ELSE 'All ages'
    END                                                     AS age_group,
    a.benes_om_cnt                                          AS traditional_medicare_people,
    ROUND(a.benes_om_cnt::NUMERIC / total.benes_om_cnt, 4)  AS share_of_traditional,
    a.tot_mdcr_stdzd_pymt_pc                                AS price_adjusted_per_person,
    a.er_visits_per_1000_benes                              AS er_visits_per_1000,
    a.ip_cvrd_stays_per_1000_benes                          AS hospital_stays_per_1000,
    a.acute_hosp_readmsn_pct                                AS readmission_rate,
    a.bene_dual_pct                                         AS medicaid_share,
    a.bene_avg_age                                          AS average_age
FROM clean.gv AS a
JOIN clean.gv AS total
    ON total.year = a.year
   AND total.geo_lvl = a.geo_lvl
   AND total.geo_desc = a.geo_desc
   AND total.age_lvl = 'All'
WHERE a.geo_lvl IN ('National', 'State');


-- 11. Rural vs urban
--     Averages are weighted by people, so a county with 500,000 people
--     counts more than one with 5,000.
DROP VIEW IF EXISTS extra.v_rural_urban;

CREATE VIEW extra.v_rural_urban AS
SELECT
    c.year,
    c.covid_year,
    r.rural_urban_group,
    COUNT(*)                                                         AS counties,
    SUM(c.benes_om_cnt)                                              AS traditional_medicare_people,
    -- weighted averages
    ROUND(SUM(c.tot_mdcr_stdzd_pymt_pc * c.benes_om_cnt)
        / SUM(CASE WHEN c.tot_mdcr_stdzd_pymt_pc IS NOT NULL THEN c.benes_om_cnt END), 2)       AS price_adjusted_per_person,
    ROUND(SUM(c.tot_mdcr_pymt_pc * c.benes_om_cnt)
        / SUM(CASE WHEN c.tot_mdcr_pymt_pc IS NOT NULL THEN c.benes_om_cnt END), 2)             AS actual_per_person,
    ROUND(SUM(c.er_visits_per_1000_benes * c.benes_om_cnt)
        / SUM(CASE WHEN c.er_visits_per_1000_benes IS NOT NULL THEN c.benes_om_cnt END), 1)     AS er_visits_per_1000,
    ROUND(SUM(c.ip_cvrd_stays_per_1000_benes * c.benes_om_cnt)
        / SUM(CASE WHEN c.ip_cvrd_stays_per_1000_benes IS NOT NULL THEN c.benes_om_cnt END), 1) AS hospital_stays_per_1000,
    ROUND(SUM(c.benes_hospc_pct * c.benes_om_cnt)
        / SUM(CASE WHEN c.benes_hospc_pct IS NOT NULL THEN c.benes_om_cnt END), 4)              AS hospice_use,
    ROUND(SUM(c.bene_dual_pct * c.benes_om_cnt)
        / SUM(CASE WHEN c.bene_dual_pct IS NOT NULL THEN c.benes_om_cnt END), 4)                AS medicaid_share_in_traditional,
    -- readmissions / hospital stays (stays = readmissions / readmission rate)
    ROUND(SUM(c.acute_hosp_readmsn_cnt)
        / SUM(c.acute_hosp_readmsn_cnt / NULLIF(c.acute_hosp_readmsn_pct, 0)), 4)               AS readmission_rate,
    -- Medicare Advantage share, same formula as CMS: MA / (MA + traditional)
    ROUND(SUM(c.benes_ma_cnt)::NUMERIC
        / SUM(CASE WHEN c.benes_ma_cnt IS NOT NULL THEN c.benes_ma_cnt + c.benes_om_cnt END), 4) AS ma_share
FROM clean.gv AS c
JOIN clean.county_rural_urban AS r
    ON r.fips = c.fips
WHERE c.geo_lvl = 'County'
GROUP BY
    c.year,
    c.covid_year,
    r.rural_urban_group;
