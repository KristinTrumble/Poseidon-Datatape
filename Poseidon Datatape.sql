-- Poseidon datatape - output lines up 1:1 with the "Data Tape" input tab (columns B:EF, header row 6),
-- same headers (line breaks in headers replaced with a space). Formula columns reproduce the input-tab
-- formulas; columns that are manual inputs are output as NULL (blank) for the team to populate.
-- Extra diagnostic columns follow EF (outside the model range).

WITH params AS (
    SELECT
        '2023-12-31'::date AS as_of_date,       -- CO2 / DT2 "Data Tape As of Date"
        0.005              AS degradation,      -- DG2 annual production degradation
        0.9                AS renewal_pct,      -- DX2 auto renewal % (used by DX, which needs DQ/DS inputs)
        '2017-12-31'::date AS ma_pbi_date,      -- DJ2
        '2020-04-30'::date AS nj_pbi_date,      -- DK2
        0                  AS dpd_min_balance,  -- a DPD bucket counts as past due only above this balance ($)
        650                AS fico_floor        -- Senior FICO triggers (EB / EC)
),

base AS (
    SELECT
        psd.*,
        v.*,
        def."total_write_offs",
        def."Deactivation Default Flag",
        def."Aging Default Flag",
        ar.agreement_number AS ar_agreement_number,
        pegu.pegu_payout_frequency,

        psd.agreement_term_years AS term_years,                                                        -- CD
        CASE WHEN psd.billing_type IN ('Full Upfront') THEN 'Prepaid' ELSE 'Monthly' END AS product_type,  -- BY
        CASE WHEN psd.billing_type = 'Fixed monthly PPA with annual reset' THEN 'Balanced' ELSE psd.billing_type END AS billing_type_based_on_proposal, -- BZ
        IFF(psd.billing_type = 'Lease', 'Lease', 'PPA') AS ppa_or_lease,                               -- BX

        CASE WHEN psd.asset_status IN ('Customer Purchased System','Force Majeure (Home Damaged)', 'Removed - Permanent', 'Force Majeure (System Damaged)','Asset Impaired- Removed Permanent', 'Asset Impaired Removed-Permanent', 'Asset Impaired Pending-Removal', 'Installed, No PTO- writeoff', 'Removed (Permanent)', 'Inactive', 'Equipment Stolen', 'Asset Impaired Pending-Removal-Billable', 'Offline', 'Bankruptcy','Damage Related Removed (Insurance claim and contract terminated)','Contract Terminated - Leave In Place') THEN 1 ELSE 0 END AS ineligible_asset_status,

        -- Aging: buckets COALESCEd to 0 so an account with no aging-report row reads as current
        (COALESCE(ar."31-60 Days Past Due",0) + COALESCE(ar."61-90 Days Past Due",0) + COALESCE(ar."91-120 Days Past Due",0)
         + COALESCE(ar."121-180 Days Past Due",0) + COALESCE(ar."181-360 Days Past Due",0) + COALESCE(ar."361+ Days Past Due",0)) AS dpd_31_bal,
        dpd_31_bal - COALESCE(ar."31-60 Days Past Due",0)  AS dpd_61_bal,
        dpd_61_bal - COALESCE(ar."61-90 Days Past Due",0)  AS dpd_91_bal,
        dpd_91_bal - COALESCE(ar."91-120 Days Past Due",0) AS dpd_121_bal,
        IFF(COALESCE(ar."1-30 Days Past Due",0) > v.dpd_min_balance AND dpd_31_bal <= v.dpd_min_balance, 1, 0) AS dpd_1_30_flag,
        IFF(dpd_31_bal  > v.dpd_min_balance, 1, 0) AS dpd_30_flag,
        IFF(dpd_61_bal  > v.dpd_min_balance, 1, 0) AS dpd_60_flag,
        IFF(dpd_91_bal  > v.dpd_min_balance, 1, 0) AS dpd_90_flag,
        IFF(dpd_121_bal > v.dpd_min_balance, 1, 0) AS dpd_120_flag,

        -- FICO (BD) = ABS data tape "Adjusted FICO". It can hold text (e.g. 'Not Available', 'Prepaid'),
        -- which TRY_TO_NUMBER turns into NULL = "No FICO" for the Senior triggers.
        abst."Adjusted FICO" AS fico,
        TRY_TO_NUMBER(fico) AS fico_num,
        COALESCE(psd.FICO_SERVICE_TRANSFER_FLAG::int, 0) AS st_flag,                       -- AY
        COALESCE(psd.previous_quarter_service_transfer_flag::int, 0) AS qtr_st_flag,       -- AZ
        psd.sales_channel = 'Multifamily - Affordable' AS is_multifamily,                  -- CH

        -- PTO / term. YEARFRAC(start, end, 1): days / average year length over the years spanned.
        DATEDIFF(day, psd.pto_date, v.as_of_date)
            / (DATEDIFF(day, DATE_FROM_PARTS(YEAR(psd.pto_date),1,1), DATE_FROM_PARTS(YEAR(v.as_of_date)+1,1,1))
               / (YEAR(v.as_of_date) - YEAR(psd.pto_date) + 1)) AS yearfrac_pto,
        CASE WHEN psd.pto_date > v.as_of_date THEN NULL
             WHEN psd.pto_date = v.as_of_date THEN 0
             ELSE yearfrac_pto * 12 END AS months_since_pto,                                -- CO
        DATEADD(month, 2, psd.pto_date) AS first_payment_date,                               -- CQ
        term_years - IFF(psd.pto_date < v.as_of_date, yearfrac_pto, 0) AS contracted_years_remaining, -- DT

        -- Contract detail
        CASE WHEN product_type = 'Prepaid' THEN 0
             WHEN billing_type_based_on_proposal = 'Generation' THEN psd.price_per_kwh
             WHEN psd.base_lease_payment_amount IS NULL THEN psd.year_1_monthly_payment * 12 / NULLIF(psd.est_yr1_gen_contract, 0)
             ELSE psd.base_lease_payment_amount * 12 / NULLIF(psd.est_yr1_gen_contract, 0) END AS implied_rate,   -- CV
        COALESCE(psd.base_battery_payment, 0) * 12 / NULLIF(psd.est_yr1_gen_contract, 0) AS battery_adder,          -- CW
        implied_rate * psd.est_yr1_gen_contract AS year_1_revenue,                                                   -- CY
        CASE WHEN psd.escalator = 0 THEN 0
             WHEN product_type = 'Prepaid' THEN 0
             WHEN ppa_or_lease = 'Lease' OR billing_type_based_on_proposal = 'Balanced'
                  THEN (1 + psd.escalator) / (1 - v.degradation) - 1
             ELSE psd.escalator END AS implied_escalator,                                                            -- DG

        -- Eligibility triggers (1 = trigger hit). 120+ DPD counts every bucket past 120 days, 361+ included.
        dpd_120_flag AS trig_120_holdco,                                                                    -- EA
        IFF(dpd_120_flag = 1 AND fico_num >= v.fico_floor, 1, 0) AS trig_120_senior,                         -- EB
        IFF(dpd_60_flag = 1 AND (fico_num IS NULL OR fico_num < v.fico_floor), 1, 0) AS trig_60_senior,     -- EC
        IFF(UPPER(TO_VARCHAR(def."Deactivation Default Flag")) IN ('1','Y','YES','TRUE'), 1, 0) AS trig_deactivated -- EE

    FROM prod_db.d_pfam.PSD_QUARTERLY_SNAPSHOT psd

    LEFT JOIN prod_db.d_pfam.quarterly_default_report AS def
        ON psd.agreement_number = def.agreement_number
        AND def.row_num IN ('1')

    LEFT JOIN prod_db.d_pfam.abs_data_tape AS abst
        ON psd.agreement_number = abst.agreement_number

    LEFT JOIN prod_db.d_pfam.abs_aging_report AS ar
        ON psd.agreement_number = ar.agreement_number
        AND ar.row_num IN ('1')

    -- Pegu payout frequency is set at contract start, so it is frozen from the current tape
    -- (see "Poseidon Pegu Payout Frequency.sql" for the one-time load).
    LEFT JOIN prod_db.d_pfam.poseidon_pegu_payout_frequency AS pegu
        ON psd.agreement_number = pegu.agreement_number

    CROSS JOIN params v

    WHERE psd.TE_FUND IN (
        'Balerion II 2021',
        'Jupiter Owner 2022',
        'Mercury 2021',
        'Pegasus 2021',
        'Ragnar 2021',
        'VSLR Restore Utah'
    )
)

SELECT
    b.agreement_number                                   AS "Agreement Number",                         -- B
    b.sc_brightbox_flag                                  AS "BrightBox",                                -- C
    b.state                                              AS "State",                                    -- D
    b.city                                               AS "City",                                     -- E
    b.county                                             AS "Customer Address",                         -- F (input tab holds county here)
    b.address                                            AS "Zip Code",                                 -- G (input tab holds full address here)
    b.utility                                            AS "Utility Company",                          -- H
    b.te_fund                                            AS "TE Fund Name",                             -- I
    b.asset_sale_date                                    AS "In TE Fund",                               -- J
    b.pbi_level                                          AS "PBI Rate $/kWh",                           -- K
    b.pbi_term                                           AS "PBI Term",                                 -- L
    b.install_date                                       AS "Install Date",                             -- M
    b.pto_date                                           AS "Actual PTO Date",                          -- N
    b.system_size                                        AS "System Size DC",                           -- O
    b.est_yr1_gen_contract                               AS "Est Yr 1 Generation",                      -- P
    b.price_per_kwh                                      AS "Price per kWh",                            -- Q
    b.base_lease_payment_amount                          AS "Monthly Base Payment",                     -- R
    b.escalator                                          AS "Annual Monthly Payment Escalator",         -- S
    b.term_years * 12                                    AS "Agreement Term (Months)",                  -- T
    b.upfront_payment_amount                             AS "Upfront Payment",                          -- U
    b.initial_deposit_amount                             AS "Deposit",                                  -- V
    b.estimated_rebate_amount                            AS "Rebate",                                   -- W
    b.avoided_cost_of_power                              AS "Year 1 Avoided Cost of Power",             -- X
    b.sr_signoff                                         AS "SR Signoff",                               -- Y
    b.billing_method                                     AS "Billing Method",                           -- Z
    b.billing_type                                       AS "Billing Type",                             -- AA
    b.asset_status                                       AS "Asset Status",                             -- AB
    b.pegu_s                                             AS "Pegu Start Year",                          -- AC
    b.proposal_name                                      AS "Proposal: Proposal ID",                    -- AD
    b.year_1_monthly_payment                             AS "Year 1 Monthly Payment",                   -- AE
    b.install_partner                                    AS "Installer",                                -- AF
    b.transfer_price                                     AS "FMV",                                      -- AG
    b.sales_channel                                      AS "Acquisition Channel",                      -- AH
    b."total_write_offs"                                 AS "Total Write Offs",                         -- AI
    NULL                                                 AS "X",                                        -- AJ
    b.panel_vendor_clean                                 AS "Panel Manufacturer",                       -- AK (clean)
    b.inverter_vendor_clean                              AS "Inverter Manufacturer",                    -- AL (clean)
    b.battery_vendor_clean                               AS "Battery Manufacturer",                     -- AM (clean)
    b.battery_model_clean                                AS "Battery Model",                            -- AN (clean)
    b.battery_count                                      AS "Number of Batteries",                      -- AO
    b.panel_vendor_clean                                 AS "Panel Manufacturer [CLEAN]",               -- AP
    b.inverter_vendor_clean                              AS "Inverter Manufacturer [CLEAN]",            -- AQ
    b.battery_vendor_clean                               AS "Battery Manufacturer [CLEAN]",             -- AR
    b.battery_model_clean                                AS "Batttery Model [CLEAN]",                   -- AS
    b.battery_capacity                                   AS "Battery Capacity kWh [CLEAN]",             -- AT
    CASE WHEN b.battery_model_clean = 'RESU 10H Prime' THEN 'RESU 10H Prime'
         WHEN COALESCE(b.battery_model_clean, '0') IN ('0', '') THEN '-'
         ELSE 'Other' END                                AS "RESU 10H Prime vs. Other",                 -- AU
    IFF(b.inverter_vendor_clean = 'Enphase', 'Micro Inverter', 'String Inverter')
                                                         AS "String or Micro",                          -- AV
    NULL                                                 AS " ",                                        -- AW
    NULL                                                 AS " ",                                        -- AX
    b.st_flag                                            AS "ST FLAG (All Time)",                       -- AY
    b.qtr_st_flag                                        AS "Current QTR ST (to be built out in future)", -- AZ
    NULL                                                 AS "Transunion FICO pulls",                    -- BA (team populates)
    b.FICO_LATEST_SERVICE_TRANSFER_SCORE                 AS "Current FICO SNF Model",                   -- BB
    NULL                                                 AS "7.30.2026 DT FICO",                        -- BC (team populates)
    b.fico                                               AS "FICO",                                     -- BD
    CASE WHEN b.pto_date IS NOT NULL THEN 'PTO'
         WHEN b.install_date IS NOT NULL THEN 'Install'
         ELSE 'PreInstall' END                           AS "Facility Status",                          -- BE
    NULL                                                 AS "X",                                        -- BF
    b.pg_threshold                                       AS "Production Guarantee %",                   -- BG
    b.pegu_payout_frequency                              AS "Pegu Payout Frequency",                    -- BH
    NULL                                                 AS "X",                                        -- BI
    1                                                    AS "0+ Days Past Due (1=Yes, 0=No)",           -- BJ
    b.dpd_1_30_flag                                      AS "1-30 Days Past Due (1=Yes, 0=No)",         -- BK
    b.dpd_30_flag                                        AS "30+ Days Past Due (1=Yes, 0=No)",          -- BL
    b.dpd_60_flag                                        AS "60+ Days Past Due (1=Yes, 0=No)",          -- BM
    b.dpd_90_flag                                        AS "90+ Days Past Due (1=Yes, 0=No)",          -- BN
    b.dpd_120_flag                                       AS "120 Days Past Due (1=Yes, 0=No)",          -- BO
    b."Aging Default Flag"                               AS "Aging Default Flag",                       -- BP
    NULL                                                 AS "X",                                        -- BQ
    b.utility || b.state                                 AS "Utility&State",                            -- BR
    b.utility                                            AS "Utility Corrected",                        -- BS
    CASE WHEN b.state = 'CA' AND b.utility IN ('SCE','PG&E','SDG&E') THEN 'IOU'
         WHEN b.state = 'CA' THEN 'Muni' END             AS "California Utility Code",                  -- BT
    CASE WHEN b.state <> 'CA' THEN b.state
         WHEN b.utility IN ('PG&E','SCE','SDG&E') THEN 'CA-' || b.utility
         ELSE 'CA-Muni' END                              AS "CA-IOU vs. CA-Muni",                       -- BU
    NULL                                                 AS "x",                                        -- BV
    RIGHT(b.proposal_name, 1)                            AS "Proposal Code",                            -- BW
    b.ppa_or_lease                                       AS "PPA or Lease",                             -- BX
    b.product_type                                       AS "Monthly Or Prepaid",                       -- BY
    b.billing_type_based_on_proposal                     AS "Billing Type Based on Proposal",           -- BZ
    IFF(b.billing_type_based_on_proposal = 'Generation', 'Generation', 'Balanced')
                                                         AS "Balanced or Generation (PPA Type)",        -- CA
    IFF(b.product_type = 'Monthly' AND b.ppa_or_lease = 'PPA' AND b.billing_type_based_on_proposal = 'Generation'
        AND b.term_years IN (20, 25), 'Generation Billing', NULL)
                                                         AS "Billing Type",                             -- CB
    b.product_type || ' ' || TO_VARCHAR(b.term_years::int) || ' Year '
        || IFF(b.product_type = 'Monthly' AND b.ppa_or_lease = 'PPA',
               "Balanced or Generation (PPA Type)" || ' ', '')
        || b.ppa_or_lease                                AS "Product Code",                             -- CC
    b.term_years                                         AS "Agreement Term (Years)",                   -- CD
    IFF(b.sc_brightbox_flag >= 1, 'Brightbox', 'Standard') AS "Brightbox",                              -- CE
    IFF(b.billing_method IN ('Recurring', 'Recurring CC'), 'Yes', 'No') AS "ACH",                       -- CF
    IFF(b.proposal_name ILIKE '%PostPTO%', 'N', 'Y')     AS "Sunrun Originated Asset (Y/N)",            -- CG
    IFF(b.is_multifamily, 'Yes', 'No')                   AS "Multifamily",                              -- CH
    b.sales_channel                                      AS "Current Channel",                          -- CI
    IFF(b.sales_channel = 'MPH', 1, 0)                   AS "Military Housing (1=Yes; 0=No)",           -- CJ
    NULL                                                 AS "X",                                        -- CK
    LAST_DAY(b.pto_date, 'quarter')                      AS "PTO Quarter",                              -- CL
    b.pto_date                                           AS "Actual & Estimated PTO Date",              -- CM
    YEAR(b.pto_date)                                     AS "PTO Year",                                 -- CN
    b.months_since_pto                                   AS "Months Since PTO",                         -- CO
    b.term_years * 12 - COALESCE(b.months_since_pto, 0)  AS "Remaining Time Contracted (Months)",       -- CP
    b.first_payment_date                                 AS "First Payment Date (Expected if No PTO)",  -- CQ
    DATEADD(month, 12 * b.term_years, b.first_payment_date)
                                                         AS "Last Payment Date (Expected if No PTO)",   -- CR
    IFF(b.pto_date IS NULL, 'No PTO', 'PTO')             AS "Actually Achieve PTO Yet?",                -- CS
    IFF(b.pto_date IS NULL, 'No PTO', 'PTO')             AS "Estimated PTO Check (at Initial Closing)", -- CT
    NULL                                                 AS "X",                                        -- CU
    b.implied_rate                                       AS "Implied $/kWh Rate (For both PPAs and Leases)", -- CV
    b.battery_adder                                      AS "Battery Adder ($/kWh)",                    -- CW
    b.implied_rate - b.battery_adder                     AS "Solar Only Rate ($/kWh)",                  -- CX
    b.year_1_revenue                                     AS "Year 1 Revenue",                           -- CY
    CASE WHEN b.product_type = 'Prepaid' THEN 0
         WHEN b.billing_type_based_on_proposal = 'Generation'
              THEN b.year_1_revenue * (((b.implied_rate * (1 + b.escalator) * b.est_yr1_gen_contract * (1 - b.degradation)) / NULLIF(b.year_1_revenue, 0)) - 1)
         ELSE b.year_1_revenue * b.escalator END         AS "Year 1 Escalator ($)",                     -- CZ
    NULL                                                 AS "Lease Refund Rate",                        -- DA (input)
    IFF(b.ppa_or_lease = 'PPA',
        -- (Upfront + Deposit) / -PV(0.5%, years, gen, 0, 1) + implied rate
        (COALESCE(b.upfront_payment_amount, 0) + COALESCE(b.initial_deposit_amount, 0))
          / NULLIF(b.est_yr1_gen_contract * (1 - POWER(1.005, -b.term_years)) / 0.005 * 1.005, 0)
          + b.implied_rate,
        0)                                               AS "PPA Refund Rate",                          -- DB
    "PPA Refund Rate" * b.est_yr1_gen_contract           AS "Year 1 Refund Rate * kWh Production",      -- DC (DA blank)
    b.year_1_revenue * b.escalator                       AS "Year 1 Revenue * Escalator",               -- DD
    b.est_yr1_gen_contract * b.pbi_level                 AS "Est 1st Year Production * PBI $ / kWh",    -- DE
    b.term_years * b.system_size                         AS "Contract Years * kW",                      -- DF
    b.implied_escalator                                  AS "Implied $/kWh Escalator",                  -- DG
    b.transfer_price / NULLIF(b.system_size, 0) / 1000   AS "FMV ($/W)",                                -- DH
    IFF(b.state = 'IL', 0, b.pbi_level)                  AS "PBI Rate ($/kWh)",                         -- DI
    IFF(b.state = 'MA' AND b.pto_date > b.ma_pbi_date, 1, 0) AS "MA PBI Flag",                          -- DJ
    IFF(b.state = 'NJ' AND b.pto_date > b.nj_pbi_date, 1, 0) AS "NJ PBI Flag",                          -- DK
    -- EOMONTH(PTO, term months) as an Excel date serial * kW
    DATEDIFF(day, '1899-12-30'::date, LAST_DAY(DATEADD(month, b.term_years * 12, b.pto_date))) * b.system_size
                                                         AS "Contracted Period End Date*kW",            -- DL
    NULL                                                 AS "X",                                        -- DM
    IFF(b.product_type = 'Monthly', b.implied_rate * POWER(1 + b.implied_escalator, b.term_years), 0)
                                                         AS "End of Contracted Rate",                   -- DN
    b.est_yr1_gen_contract * POWER(1 - b.degradation, b.term_years)
                                                         AS "Implied End of Contracted Period Production (Contract)", -- DO
    "Implied End of Contracted Period Production (Contract)" * "End of Contracted Rate"
                                                         AS "End of Contract Payments",                 -- DP
    NULL                                                 AS "Estimated 2022 Utility Rate ($/kWh)",      -- DQ (input)
    NULL                                                 AS "2022 Utility Rate * 2022 Contracted Production", -- DR (needs DQ)
    NULL                                                 AS "Assumed Utility Rate Escalator",           -- DS (input)
    b.contracted_years_remaining                         AS "Contracted Years Remaining",               -- DT
    NULL                                                 AS "Implied End of Contract Utility Rate",     -- DU (needs DQ, DS)
    NULL                                                 AS "Implied End of Contract Utility Payment",  -- DV (needs DU)
    NULL                                                 AS "PA Consulting Escalator * Contracted Years Remaining", -- DW (needs DS)
    NULL                                                 AS "Auto Renewal Annual Payment",              -- DX (needs DU)
    NULL                                                 AS "x",                                        -- DY
    NULL                                                 AS "7/31/2026 PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- DZ (team populates)
    b.trig_120_holdco                                    AS "120+ dpd (Holdco only)",                   -- EA
    b.trig_120_senior                                    AS "120+ dpd (361+ not resolved) and FICO =>650 (Senior only)", -- EB
    b.trig_60_senior                                     AS "60+ dpd and No FICO or FICO <650 (Senior only)", -- EC
    b.ineligible_asset_status                            AS "Ineligible Asset Status",                  -- ED
    b.trig_deactivated                                   AS "Deactivated",                              -- EE
    -- No current Senior trigger. Not re-eligible: final eligibility = MIN(DZ, EF) once DZ is populated.
    IFF(b.trig_120_senior + b.trig_60_senior + b.ineligible_asset_status + b.trig_deactivated = 0, 1, 0)
                                                         AS "10/30/2026 PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- EF

    -- Diagnostics (right of EF, outside the model range)
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
        IFF(b.ineligible_asset_status = 1, 'Asset Status: ' || b.asset_status, NULL),
        IFF(b.trig_deactivated = 1, 'Deactivated', NULL),
        IFF(b.trig_120_senior = 1, 'Senior: 120+ DPD, FICO >= 650', NULL),
        IFF(b.trig_60_senior = 1,
            IFF(b.fico_num IS NULL, 'Senior: 60+ DPD, no FICO', 'Senior: 60+ DPD, FICO < 650'), NULL),
        IFF(b.trig_120_holdco = 1, 'Holdco: 120+ DPD', NULL)
    ), '; ')                                             AS "Ineligible Reason",
    IFF(b.ar_agreement_number IS NULL, 1, 0)             AS "No Aging Record"

FROM base b
ORDER BY b.agreement_number;
