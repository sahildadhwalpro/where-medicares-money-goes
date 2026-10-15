# Where Medicare's Money Goes: methodology and checks

## Data
- CMS Medicare Geographic Variation Public Use File, 2014-2024 (national, state, county).
- Traditional (fee-for-service) Medicare only: people with both Part A and Part B.
- BLS Consumer Price Index (CPI-U, US city average, annual average) for inflation.
- USDA Rural-Urban Continuum Codes, 2023 (2013 codes for Connecticut's old counties). Used only in the extra analysis.
- Removed: territories (PR, VI, "Territory", "ZZ") and "UNKNOWN" county rows. Counties under 1,000 people are left out of county maps and rankings. Values CMS suppresses ("*", under 11 people) are left blank.

## Definitions
- **Spending per person**: CMS price-adjusted (standardized) Medicare payment per traditional Medicare person. It removes local price differences (wages, teaching-hospital add-ons). It does **not** remove inflation.
- **Readmission rate**: share of hospital stays followed by another stay within 30 days (all-cause).
- **Medicare Advantage share**: MA / (MA + traditional), people with Part A and Part B.
- **Post-acute care**: skilled nursing facilities, home health, inpatient rehab and long-term care hospitals.
- **County gap**: 90th minus 10th percentile county, counties with 1,000+ people.

## How the numbers were checked
Every number on the dashboard is recomputed in `sql/08_key_findings.sql`, with the expected value written next to each query.

## Tab 1: Cost trend ("Up 37%, but mostly inflation")
- US spending per person: $9,191 (2014) to $12,553 (2024) = **+36.6%**.
- CPI-U went from 236.736 (2014) to 313.689 (2024) = +32.5%.
- In 2014 dollars, 2024 spending is $12,553 x 236.736 / 313.689 = **$9,474**, so real growth is **+3.1%**.
- The bar split: inflation = 2014 spending x (CPI that year / CPI 2014 - 1); real growth = what's left. In 2024: $9,191 + $2,987 (inflation) + $375 (real growth) = $12,553.
- **2019 as the midpoint** (2020 is distorted by COVID): $9,191 + $735 (inflation) + $479 (real growth) = $10,404. In 2014 dollars that is $9,634, higher than 2024's $9,474. So all the real growth happened before COVID, and since then inflation drove the increase.
- **Where the extra $3,363 went**, by type of care: outpatient +$1,249, doctor and clinic +$1,147, medical equipment +$391, hospital stays +$258, hospice +$165, post-acute care +$152. These add up to $3,363. Same dollar basis as the headline (price-adjusted, not inflation-adjusted).
- Hospital stays per 1,000 people fell from 282 to 225 (-20%).
- Medicare Advantage share went from 32% (2014) to 41% (2019) to 55% (2024). The people still in traditional Medicare are a different group than in 2014, so spending per person can move because of who is left, not only because care changed.

## Tab 2: County gap ("Post-acute care drives the county gap")
- 2,592 counties with 1,000+ people (2024). 10th percentile $10,148, 90th percentile $14,398: a gap of **$4,250** per person.
- Method: variance decomposition. Total spending = sum of 18 types of care. For each type: share = covariance(type, total) / variance(total). The 18 shares add to exactly 100%, so they can be added up into 6 groups.
- Post-acute care = **36%**, doctor and clinic = 25%, hospital stays = 19%.
- Robustness: post-acute care is between 36% and 43% in every year 2014-2024, and 32% if counties are weighted by people.
- This shows where county differences sit, not what causes them.

## Tab 3: Readmissions ("Extra readmissions cost $621M a year")
- US readmission rate: 18.1% in 2014 and 18.1% in 2024 (17.8% to 18.1% every year).
- $621M estimate (2024):
  1. Counties with 1,000+ people and a readmission rate above the US rate (18.07%): 878 counties.
  2. Hospital stays in each county = readmissions / readmission rate.
  3. Extra readmissions = stays x (county rate - US rate). Sum = **48,499**.
  4. Cost per hospital stay = US price-adjusted hospital spending per person / hospital stays per person = $2,879 / 0.2248 = **$12,804**.
  5. 48,499 x $12,804 = **$621M**.
- Other ways to count it:

| Change | Result |
|---|---|
| Include counties under 1,000 people | $631M |
| Actual (not price-adjusted) cost per stay ($16,933) | $821M |
| Median county as the benchmark instead of the US rate | $1.1B |

- Where to start: the top 10 states hold 70% of the extra readmissions, and the top 100 counties (of 878) hold 68%.
- What it is not: guaranteed savings. It is the spending tied to readmissions above the national rate. Readmissions are all-cause (some are planned), and a readmission may cost more or less than an average stay.

## Limits
- Traditional Medicare only (under half of Medicare in 2024).
- 2020-2021 are distorted by COVID.
- Home health counting changed in 2020 (60-day episodes became 30-day periods).
- Connecticut switched to 9 planning regions in 2022, so its county trend breaks.
- County-level data, not patient-level: these are associations, not causes. Lower spending is not automatically better.

## How it was built
- PostgreSQL: raw load (246 text columns), clean table (69 typed columns), 12 data quality checks, 6 views for the dashboard (schema `tableau`), 11 extra views I explored but left off the dashboard (schema `extra`), CSV exports, and a findings script that recomputes every number on the dashboard.
- Tableau Public: 3 dashboards, one question each (Cost trend, County gap, Readmissions). Sources and the full $621M calculation are in tooltips.
