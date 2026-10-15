-- =============================================================
-- 03  Clean table (PostgreSQL)
-- raw.gv_raw (246 text columns) -> clean.gv (69 typed columns)
--
-- What this step does:
--   1. Turns "*" (suppressed, fewer than 11 people) into NULL.
--      The avoidable-stay (PQI) columns also use "NA", so those get a second NULLIF.
--   2. Changes text to numbers
--   3. Removes rows we don't use:
--        territories (PR, VI, "Territory", "ZZ") and "UNKNOWN" county rows
--   4. Adds helper columns: state_code, county_name, covid_year, small_county
--
-- I kept the CMS column names (in lower case) so every number can be
-- traced back to the CMS data dictionary.
-- "_pct" columns are fractions: 0.18 = 18%.
-- "stdzd" = price-adjusted (standardized) spending.
-- =============================================================


DROP TABLE IF EXISTS clean.gv CASCADE;

CREATE TABLE clean.gv AS
SELECT
    -- IDs
    year::INT                                               AS year,
    bene_geo_lvl                                            AS geo_lvl,          -- National / State / County
    bene_geo_desc                                           AS geo_desc,         -- e.g. 'MA-Worcester'
    bene_geo_cd                                             AS fips,
    bene_age_lvl                                            AS age_lvl,          -- All / <65 / >=65
    CASE
        WHEN bene_geo_lvl = 'National' THEN 'US'
        ELSE SPLIT_PART(bene_geo_desc, '-', 1)
    END                                                     AS state_code,
    CASE
        WHEN bene_geo_lvl = 'County' THEN SUBSTRING(bene_geo_desc FROM 4)
    END                                                     AS county_name,

    -- Who is covered
    NULLIF(benes_total_cnt, '*')::BIGINT                    AS benes_total_cnt,                     -- everyone on Medicare
    NULLIF(benes_om_cnt, '*')::BIGINT                       AS benes_om_cnt,                        -- traditional Medicare
    NULLIF(benes_ma_cnt, '*')::BIGINT                       AS benes_ma_cnt,                        -- Medicare Advantage
    NULLIF(ma_prtcptn_rate, '*')::NUMERIC                   AS ma_prtcptn_rate,
    NULLIF(bene_avg_age, '*')::NUMERIC                      AS bene_avg_age,
    NULLIF(bene_feml_pct, '*')::NUMERIC                     AS bene_feml_pct,
    NULLIF(bene_dual_pct, '*')::NUMERIC                     AS bene_dual_pct,                       -- also on Medicaid

    -- Total spending
    NULLIF(tot_mdcr_pymt_amt, '*')::NUMERIC                 AS tot_mdcr_pymt_amt,                   -- actual $
    NULLIF(tot_mdcr_stdzd_pymt_amt, '*')::NUMERIC           AS tot_mdcr_stdzd_pymt_amt,             -- price-adjusted $
    NULLIF(tot_mdcr_pymt_pc, '*')::NUMERIC                  AS tot_mdcr_pymt_pc,                    -- actual $ per person
    NULLIF(tot_mdcr_stdzd_pymt_pc, '*')::NUMERIC            AS tot_mdcr_stdzd_pymt_pc,              -- price-adjusted $ per person
    NULLIF(ip_mdcr_pymt_pc, '*')::NUMERIC                   AS ip_mdcr_pymt_pc,                     -- actual $ per person, hospital stays (readmission estimate)

    -- Price-adjusted $ per person, by type of care
    NULLIF(ip_mdcr_stdzd_pymt_pc, '*')::NUMERIC             AS ip_mdcr_stdzd_pymt_pc,               -- hospital stays
    NULLIF(op_mdcr_stdzd_pymt_pc, '*')::NUMERIC             AS op_mdcr_stdzd_pymt_pc,               -- hospital outpatient
    NULLIF(asc_mdcr_stdzd_pymt_pc, '*')::NUMERIC            AS asc_mdcr_stdzd_pymt_pc,              -- surgery centers
    NULLIF(snf_mdcr_stdzd_pymt_pc, '*')::NUMERIC            AS snf_mdcr_stdzd_pymt_pc,              -- skilled nursing
    NULLIF(irf_mdcr_stdzd_pymt_pc, '*')::NUMERIC            AS irf_mdcr_stdzd_pymt_pc,              -- inpatient rehab
    NULLIF(ltch_mdcr_stdzd_pymt_pc, '*')::NUMERIC           AS ltch_mdcr_stdzd_pymt_pc,             -- long-term care hospital
    NULLIF(hh_mdcr_stdzd_pymt_pc, '*')::NUMERIC             AS hh_mdcr_stdzd_pymt_pc,               -- home health
    NULLIF(hospc_mdcr_stdzd_pymt_pc, '*')::NUMERIC          AS hospc_mdcr_stdzd_pymt_pc,            -- hospice
    NULLIF(em_mdcr_stdzd_pymt_pc, '*')::NUMERIC             AS em_mdcr_stdzd_pymt_pc,               -- doctor visits
    NULLIF(prcdrs_mdcr_stdzd_pymt_pc, '*')::NUMERIC         AS prcdrs_mdcr_stdzd_pymt_pc,           -- procedures
    NULLIF(tests_mdcr_stdzd_pymt_pc, '*')::NUMERIC          AS tests_mdcr_stdzd_pymt_pc,            -- tests
    NULLIF(imgng_mdcr_stdzd_pymt_pc, '*')::NUMERIC          AS imgng_mdcr_stdzd_pymt_pc,            -- imaging
    NULLIF(dme_mdcr_stdzd_pymt_pc, '*')::NUMERIC            AS dme_mdcr_stdzd_pymt_pc,              -- medical equipment
    NULLIF(trtmnts_mdcr_stdzd_pymt_pc, '*')::NUMERIC        AS trtmnts_mdcr_stdzd_pymt_pc,          -- treatments (mostly clinic drugs)
    NULLIF(amblnc_mdcr_stdzd_pymt_pc, '*')::NUMERIC         AS amblnc_mdcr_stdzd_pymt_pc,           -- ambulance
    NULLIF(op_dlys_mdcr_stdzd_pymt_pc, '*')::NUMERIC        AS op_dlys_mdcr_stdzd_pymt_pc,          -- outpatient dialysis
    NULLIF(fqhc_rhc_mdcr_stdzd_pymt_pc, '*')::NUMERIC       AS fqhc_rhc_mdcr_stdzd_pymt_pc,         -- community and rural clinics

    -- Use of care
    NULLIF(ip_cvrd_stays_per_1000_benes, '*')::NUMERIC      AS ip_cvrd_stays_per_1000_benes,
    NULLIF(er_visits_per_1000_benes, '*')::NUMERIC          AS er_visits_per_1000_benes,
    NULLIF(op_visits_per_1000_benes, '*')::NUMERIC          AS op_visits_per_1000_benes,
    NULLIF(snf_cvrd_stays_per_1000_benes, '*')::NUMERIC     AS snf_cvrd_stays_per_1000_benes,
    NULLIF(irf_cvrd_stays_per_1000_benes, '*')::NUMERIC     AS irf_cvrd_stays_per_1000_benes,
    NULLIF(hh_episodes_per_1000_benes, '*')::NUMERIC        AS hh_episodes_per_1000_benes,
    NULLIF(benes_hospc_pct, '*')::NUMERIC                   AS benes_hospc_pct,

    -- Quality
    NULLIF(acute_hosp_readmsn_cnt, '*')::BIGINT             AS acute_hosp_readmsn_cnt,
    NULLIF(acute_hosp_readmsn_pct, '*')::NUMERIC            AS acute_hosp_readmsn_pct,

    -- Avoidable hospital stays per 100,000 (state and national rows only)
    NULLIF(NULLIF(pqi03_dbts_age_lt_65, '*'), 'NA')::NUMERIC AS pqi03_dbts_age_lt_65,
    NULLIF(NULLIF(pqi03_dbts_age_65_74, '*'), 'NA')::NUMERIC AS pqi03_dbts_age_65_74,
    NULLIF(NULLIF(pqi03_dbts_age_ge_75, '*'), 'NA')::NUMERIC AS pqi03_dbts_age_ge_75,
    NULLIF(NULLIF(pqi05_copd_asthma_age_40_64, '*'), 'NA')::NUMERIC AS pqi05_copd_asthma_age_40_64,
    NULLIF(NULLIF(pqi05_copd_asthma_age_65_74, '*'), 'NA')::NUMERIC AS pqi05_copd_asthma_age_65_74,
    NULLIF(NULLIF(pqi05_copd_asthma_age_ge_75, '*'), 'NA')::NUMERIC AS pqi05_copd_asthma_age_ge_75,
    NULLIF(NULLIF(pqi07_hyprtnsn_age_lt_65, '*'), 'NA')::NUMERIC AS pqi07_hyprtnsn_age_lt_65,
    NULLIF(NULLIF(pqi07_hyprtnsn_age_65_74, '*'), 'NA')::NUMERIC AS pqi07_hyprtnsn_age_65_74,
    NULLIF(NULLIF(pqi07_hyprtnsn_age_ge_75, '*'), 'NA')::NUMERIC AS pqi07_hyprtnsn_age_ge_75,
    NULLIF(NULLIF(pqi08_chf_age_lt_65, '*'), 'NA')::NUMERIC AS pqi08_chf_age_lt_65,
    NULLIF(NULLIF(pqi08_chf_age_65_74, '*'), 'NA')::NUMERIC AS pqi08_chf_age_65_74,
    NULLIF(NULLIF(pqi08_chf_age_ge_75, '*'), 'NA')::NUMERIC AS pqi08_chf_age_ge_75,
    NULLIF(NULLIF(pqi11_bctrl_pna_age_lt_65, '*'), 'NA')::NUMERIC AS pqi11_bctrl_pna_age_lt_65,
    NULLIF(NULLIF(pqi11_bctrl_pna_age_65_74, '*'), 'NA')::NUMERIC AS pqi11_bctrl_pna_age_65_74,
    NULLIF(NULLIF(pqi11_bctrl_pna_age_ge_75, '*'), 'NA')::NUMERIC AS pqi11_bctrl_pna_age_ge_75,
    NULLIF(NULLIF(pqi12_uti_age_lt_65, '*'), 'NA')::NUMERIC AS pqi12_uti_age_lt_65,
    NULLIF(NULLIF(pqi12_uti_age_65_74, '*'), 'NA')::NUMERIC AS pqi12_uti_age_65_74,
    NULLIF(NULLIF(pqi12_uti_age_ge_75, '*'), 'NA')::NUMERIC AS pqi12_uti_age_ge_75,
    NULLIF(NULLIF(pqi15_asthma_age_lt_40, '*'), 'NA')::NUMERIC AS pqi15_asthma_age_lt_40,
    NULLIF(NULLIF(pqi16_lwrxtrmty_amputn_age_lt_65, '*'), 'NA')::NUMERIC AS pqi16_lwrxtrmty_amputn_age_lt_65,
    NULLIF(NULLIF(pqi16_lwrxtrmty_amputn_age_65_74, '*'), 'NA')::NUMERIC AS pqi16_lwrxtrmty_amputn_age_65_74,
    NULLIF(NULLIF(pqi16_lwrxtrmty_amputn_age_ge_75, '*'), 'NA')::NUMERIC AS pqi16_lwrxtrmty_amputn_age_ge_75,

    -- Helper columns
    CASE
        WHEN year IN ('2020', '2021') THEN 'Yes'
        ELSE 'No'
    END                                                     AS covid_year,
    CASE
        WHEN bene_geo_lvl = 'County' AND COALESCE(NULLIF(benes_om_cnt, '*')::INT, 0) < 1000 THEN 'Yes'
        ELSE 'No'
    END                                                     AS small_county       -- under 1,000 people: numbers are noisy
FROM raw.gv_raw
WHERE bene_geo_lvl = 'National'
   OR (bene_geo_lvl = 'State'  AND bene_geo_desc NOT IN ('PR', 'VI', 'Territory', 'ZZ'))
   OR (bene_geo_lvl = 'County' AND bene_geo_desc NOT LIKE '%-UNKNOWN' AND bene_geo_desc NOT LIKE 'VI-%');


-- Quick check: rows by level and age group
SELECT
    geo_lvl,
    age_lvl,
    COUNT(*)  AS rows,
    MIN(year) AS first_year,
    MAX(year) AS last_year
FROM clean.gv
GROUP BY
    geo_lvl,
    age_lvl
ORDER BY
    geo_lvl,
    age_lvl;
