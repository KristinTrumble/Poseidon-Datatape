-- Poseidon datatape - output columns A:EE line up 1:1 with the "Poseidon DT for Model" input page,
-- using the same headers (line breaks in headers replaced with a space). Columns with no source in
-- Snowflake are output as NULL (blank) so the layout is preserved. Extra diagnostic columns follow EE.

WITH params AS (
    SELECT
        '2023-12-31'::date AS cutoff_date,      -- as-of date for "Months Since PTO" (reproduces the current model)
        0                  AS dpd_min_balance,  -- a DPD bucket counts as past due only above this balance ($)
        650                AS fico_floor        -- Senior FICO triggers: 120+ dpd and FICO >= 650 / 60+ dpd and no FICO or FICO < 650
),

base AS (
    SELECT
        psd.*,
        def."total_write_offs",
        def."Deactivation Default Flag",
        def."Aging Default Flag",
        ar.agreement_number AS ar_agreement_number,

        CASE WHEN psd.billing_type IN ('Full Upfront') THEN 'Prepaid' ELSE 'Monthly' END AS product_type,
        CASE WHEN psd.billing_type = 'Fixed monthly PPA with annual reset' THEN 'Balanced' ELSE psd.billing_type END AS billing_type_based_on_proposal,

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

        -- Latest FICO: FICO_LATEST_SERVICE_TRANSFER_SCORE is the current customer's score (equals the original
        -- score when there has been no service transfer). Stored as VARCHAR, so TRY_TO_NUMBER turns text such as
        -- 'Not Available' into NULL; fall back to the original score only when the latest is missing.
        COALESCE(TRY_TO_NUMBER(psd.FICO_LATEST_SERVICE_TRANSFER_SCORE), TRY_TO_NUMBER(psd.fico_original_score)) AS latest_fico,

        -- PTO / term
        ROUND(DATEDIFF(day, psd.pto_date, v.cutoff_date) / (365/12), 2) AS months_since_pto,
        psd.agreement_term_years * 12 - months_since_pto AS remaining_months,
        DATEADD(month, 2, psd.pto_date) AS first_payment_date,

        -- Economics
        IFF(psd.billing_type = 'Lease', psd.base_lease_payment_amount * 12, psd.price_per_kwh * psd.est_yr1_gen_contract) AS year_1_revenue,
        year_1_revenue / NULLIF(psd.est_yr1_gen_contract, 0) AS implied_rate,
        COALESCE(psd.base_battery_payment, 0) * 12 / NULLIF(psd.est_yr1_gen_contract, 0) AS battery_adder,

        -- Eligibility triggers (1 = trigger hit). 120+ DPD counts every bucket past 120 days, 361+ included.
        dpd_120_flag AS trig_120_holdco,
        IFF(dpd_120_flag = 1 AND latest_fico >= v.fico_floor, 1, 0) AS trig_120_senior,
        IFF(dpd_60_flag = 1 AND (latest_fico IS NULL OR latest_fico < v.fico_floor), 1, 0) AS trig_60_senior,
        IFF(UPPER(TO_VARCHAR(def."Deactivation Default Flag")) IN ('1','Y','YES','TRUE'), 1, 0) AS trig_deactivated

    FROM prod_db.d_pfam.PSD_QUARTERLY_SNAPSHOT psd

    LEFT JOIN prod_db.d_pfam.quarterly_default_report AS def
        ON psd.agreement_number = def.agreement_number
        AND def.row_num IN ('1')

    LEFT JOIN prod_db.d_pfam.abs_aging_report AS ar
        ON psd.agreement_number = ar.agreement_number
        AND ar.row_num IN ('1')

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
    b.agreement_number                                   AS "Agreement Number",                         -- A
    b.sc_brightbox_flag                                  AS "BrightBox",                                -- B
    b.state                                              AS "State",                                    -- C
    b.city                                               AS "City",                                     -- D
    b.county                                             AS "Customer Address",                         -- E (model holds county here)
    b.address                                            AS "Zip Code",                                 -- F (model holds full address here)
    b.utility                                            AS "Utility Company",                          -- G
    b.te_fund                                            AS "TE Fund Name",                             -- H
    b.asset_sale_date                                    AS "In TE Fund",                               -- I
    b.pbi_level                                          AS "PBI Rate $/kWh",                           -- J
    b.pbi_term                                           AS "PBI Term",                                 -- K
    b.install_date                                       AS "Install Date",                             -- L
    b.pto_date                                           AS "Actual PTO Date",                          -- M
    b.system_size                                        AS "System Size DC",                           -- N
    b.est_yr1_gen_contract                               AS "Est Yr 1 Generation",                      -- O
    b.price_per_kwh                                      AS "Price per kWh",                            -- P
    b.base_lease_payment_amount                          AS "Monthly Base Payment",                     -- Q
    b.escalator                                          AS "Annual Monthly Payment Escalator",         -- R
    b.agreement_term_years * 12                          AS "Agreement Term (Months)",                  -- S
    b.upfront_payment_amount                             AS "Upfront Payment",                          -- T
    b.initial_deposit_amount                             AS "Deposit",                                  -- U
    b.estimated_rebate_amount                            AS "Rebate",                                   -- V
    b.avoided_cost_of_power                              AS "Year 1 Avoided Cost of Power",             -- W
    TO_DATE(b.sr_signoff)                                AS "SR Signoff",                               -- X
    b.billing_method                                     AS "Billing Method",                           -- Y
    b.billing_type                                       AS "Billing Type",                             -- Z
    b.asset_status                                       AS "Asset Status",                             -- AA
    b.pegu_s                                             AS "Pegu Start Year",                          -- AB
    b.proposal_name                                      AS "Proposal: Proposal ID",                    -- AC
    b.year_1_monthly_payment                             AS "Year 1 Monthly Payment",                   -- AD
    b.install_partner                                    AS "Installer",                                -- AE
    b.transfer_price                                     AS "FMV",                                      -- AF
    b.sales_channel                                      AS "Acquisition Channel",                      -- AG
    b."total_write_offs"                                 AS "Total Write Offs",                         -- AH
    NULL                                                 AS "X",                                        -- AI
    NULL                                                 AS "Panel Manufacturer",                       -- AJ (raw vendor not in PSD)
    NULL                                                 AS "Inverter Manufacturer",                    -- AK (raw vendor not in PSD)
    NULL                                                 AS "Battery Manufacturer",                     -- AL (raw vendor not in PSD)
    NULL                                                 AS "Battery Model",                            -- AM (raw model not in PSD)
    b.battery_count                                      AS "Number of Batteries",                      -- AN
    b.panel_vendor_clean                                 AS "Panel Manufacturer [CLEAN]",               -- AO
    b.inverter_vendor_clean                              AS "Inverter Manufacturer [CLEAN]",            -- AP
    b.battery_vendor_clean                               AS "Battery Manufacturer [CLEAN]",             -- AQ
    b.battery_model_clean                                AS "Batttery Model [CLEAN]",                   -- AR
    b.battery_capacity                                   AS "Battery Capacity kWh [CLEAN]",             -- AS
    CASE WHEN COALESCE(b.battery_count, 0) = 0 THEN '-'
         WHEN b.battery_model_clean = 'RESU 10H Prime' THEN 'RESU 10H Prime'
         ELSE 'Other' END                                AS "RESU 10H Prime vs. Other",                 -- AT
    IFF(b.inverter_vendor_clean ILIKE '%Enphase%', 'Micro Inverter', 'String Inverter')
                                                         AS "String or Micro",                          -- AU
    NULL                                                 AS " ",                                        -- AV
    NULL                                                 AS " ",                                        -- AW
    b.FICO_SERVICE_TRANSFER_FLAG                         AS "ST FLAG (All Time)",                       -- AX
    b.previous_quarter_service_transfer_flag             AS "Current QTR ST (to be built out in future)", -- AY
    NULL                                                 AS "Transunion FICO pulls",                    -- AZ
    TRY_TO_NUMBER(b.FICO_LATEST_SERVICE_TRANSFER_SCORE)  AS "Current FICO SNF Model",                   -- BA
    NULL                                                 AS "7.30.2026 DT FICO",                        -- BB (prior tape)
    b.latest_fico                                        AS "FICO",                                     -- BC
    NULL                                                 AS "Facility Status",                          -- BD
    NULL                                                 AS "X",                                        -- BE
    b.pg_threshold                                       AS "Production Guarantee %",                   -- BF
    NULL                                                 AS "Pegu Payout Frequency",                    -- BG
    NULL                                                 AS " ",                                        -- BH
    1                                                    AS "0+ Days Past Due (1=Yes, 0=No)",           -- BI
    b.dpd_1_30_flag                                      AS "1-30 Days Past Due (1=Yes, 0=No)",         -- BJ
    b.dpd_30_flag                                        AS "30+ Days Past Due (1=Yes, 0=No)",          -- BK
    b.dpd_60_flag                                        AS "60+ Days Past Due (1=Yes, 0=No)",          -- BL
    b.dpd_90_flag                                        AS "90+ Days Past Due (1=Yes, 0=No)",          -- BM
    b.dpd_120_flag                                       AS "120 Days Past Due (1=Yes, 0=No)",          -- BN
    b."Aging Default Flag"                               AS "Aging Default Flag",                       -- BO
    NULL                                                 AS "X",                                        -- BP
    b.utility || b.state                                 AS "Utility&State",                            -- BQ
    b.psd_clean_utility                                  AS "Utility Corrected",                        -- BR
    CASE WHEN b.state <> 'CA' THEN NULL
         WHEN b.utility IN ('PG&E','SCE','SDG&E') THEN 'IOU'
         ELSE 'Muni' END                                 AS "California Utility Code",                  -- BS
    CASE WHEN b.state <> 'CA' THEN b.state
         WHEN b.utility IN ('PG&E','SCE','SDG&E') THEN 'CA-' || b.utility
         ELSE 'CA-Muni' END                              AS "CA-IOU vs. CA-Muni",                       -- BT
    NULL                                                 AS " ",                                        -- BU
    SPLIT_PART(b.proposal_name, '-', -1)                 AS "Proposal Code",                            -- BV
    IFF(b.billing_type = 'Lease', 'Lease', 'PPA')        AS "PPA or Lease",                             -- BW
    b.product_type                                       AS "Monthly Or Prepaid",                       -- BX
    b.billing_type_based_on_proposal                     AS "Billing Type Based on Proposal",           -- BY
    IFF(b.billing_type = 'Generation', 'Generation', 'Balanced')
                                                         AS "Balanced or Generation (PPA Type)",        -- BZ
    IFF(b.billing_type = 'Generation', 'Generation Billing', NULL)
                                                         AS "Billing Type",                             -- CA
    b.product_type || ' ' || TO_VARCHAR(b.agreement_term_years::int) || ' Year '
        || IFF(b.billing_type = 'Lease', 'Lease', b.billing_type_based_on_proposal || ' PPA')
                                                         AS "Product Code",                             -- CB
    b.agreement_term_years                               AS "Agreement Term (Years)",                   -- CC
    IFF(b.sc_brightbox_flag = 1, 'Brightbox', 'Standard') AS "Brightbox",                               -- CD
    IFF(b.billing_method = 'Recurring', 'Yes', 'No')     AS "ACH",                                      -- CE
    NULL                                                 AS "Sunrun Originated Asset (Y/N)",            -- CF
    IFF(b.multifamily_flag = 1, 'Yes', 'No')             AS "Multifamily",                              -- CG
    b.sales_channel                                      AS "Current Channel",                          -- CH
    b.military_housing_flag                              AS "Military Housing (1=Yes; 0=No)",           -- CI
    NULL                                                 AS " ",                                        -- CJ
    LAST_DAY(b.pto_date, 'quarter')                      AS "PTO Quarter",                              -- CK
    b.pto_date                                           AS "Actual & Estimated PTO Date",              -- CL
    YEAR(b.pto_date)                                     AS "PTO Year",                                 -- CM
    b.months_since_pto                                   AS "Months Since PTO",                         -- CN
    ROUND(b.remaining_months)                            AS "Remaining Time Contracted (Months)",       -- CO
    b.first_payment_date                                 AS "First Payment Date (Expected if No PTO)",  -- CP
    DATEADD(year, b.agreement_term_years, b.first_payment_date)
                                                         AS "Last Payment Date (Expected if No PTO)",   -- CQ
    IFF(b.pto_date IS NOT NULL, 'PTO', 'No PTO')         AS "Actually Achieve PTO Yet?",                -- CR
    NULL                                                 AS "Estimated PTO Check (at Initial Closing)", -- CS
    NULL                                                 AS "X",                                        -- CT
    b.implied_rate                                       AS "Implied $/kWh Rate (For both PPAs and Leases)", -- CU
    NULLIF(b.battery_adder, 0)                           AS "Battery Adder ($/kWh)",                    -- CV
    b.implied_rate - b.battery_adder                     AS "Solar Only Rate ($/kWh)",                  -- CW
    b.year_1_revenue                                     AS "Year 1 Revenue",                           -- CX
    b.year_1_revenue * b.escalator                       AS "Year 1 Escalator ($)",                     -- CY
    NULL                                                 AS "Lease Refund Rate",                        -- CZ
    NULL                                                 AS "PPA Refund Rate",                          -- DA
    NULL                                                 AS "Year 1 Refund Rate * kWh Production",      -- DB
    b.year_1_revenue * b.escalator                       AS "Year 1 Revenue * Escalator",               -- DC
    NULLIF(b.est_yr1_gen_contract * b.pbi_level, 0)      AS "Est 1st Year Production * PBI $ / kWh",    -- DD
    b.agreement_term_years * b.system_size               AS "Contract Years * kW",                      -- DE
    NULL                                                 AS "Implied $/kWh Escalator",                  -- DF
    b.transfer_price / NULLIF(b.system_size * 1000, 0)   AS "FMV ($/W)",                                -- DG
    NULLIF(b.pbi_level, 0)                               AS "PBI Rate ($/kWh)",                         -- DH
    IFF(b.state = 'MA', 1, 0)                            AS "MA PBI Flag",                              -- DI
    IFF(b.state = 'NJ', 1, 0)                            AS "NJ PBI Flag",                              -- DJ
    NULL                                                 AS "Contracted Period End Date*kW",            -- DK
    NULL                                                 AS " ",                                        -- DL
    NULL                                                 AS "End of Contracted Rate",                   -- DM
    NULL                                                 AS "Implied End of Contracted Period Production (Contract)", -- DN
    NULL                                                 AS "End of Contract Payments",                 -- DO
    NULL                                                 AS "Estimated 2022 Utility Rate ($/kWh)",      -- DP
    NULL                                                 AS "2022 Utility Rate * 2022 Contracted Production", -- DQ
    NULL                                                 AS "Assumed Utility Rate Escalator",           -- DR
    ROUND(b.remaining_months / 12, 2)                    AS "Contracted Years Remaining",               -- DS
    NULL                                                 AS "Implied End of Contract Utility Rate",     -- DT
    NULL                                                 AS "Implied End of Contract Utility Payment",  -- DU
    NULL                                                 AS "PA Consulting Escalator * Contracted Years Remaining", -- DV
    NULL                                                 AS "Auto Renewal Annual Payment",              -- DW
    NULL                                                 AS " ",                                        -- DX
    NULL                                                 AS "7/31/2026 PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- DY (prior tape)
    b.trig_120_holdco                                    AS "120+ dpd (Holdco only)",                   -- DZ
    b.trig_120_senior                                    AS "120+ dpd (361+ not resolved) and FICO =>650 (Senior only)", -- EA
    b.trig_60_senior                                     AS "60+ dpd and No FICO or FICO <650 (Senior only)", -- EB
    b.ineligible_asset_status                            AS "Ineligible Asset Status",                  -- EC
    b.trig_deactivated                                   AS "Deactivated",                              -- ED
    IFF(b.trig_120_holdco + b.trig_120_senior + b.trig_60_senior + b.ineligible_asset_status + b.trig_deactivated = 0, 1, 0)
                                                         AS "10/30/2026 PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- EE

    -- Diagnostics (right of EE, outside the model range)
    IFF(b.trig_120_senior + b.trig_60_senior + b.ineligible_asset_status + b.trig_deactivated = 0, 1, 0)
                                                         AS "Eligible - Senior triggers only",
    IFF(b.trig_120_holdco + b.ineligible_asset_status + b.trig_deactivated = 0, 1, 0)
                                                         AS "Eligible - Holdco triggers only",
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
        IFF(b.ineligible_asset_status = 1, 'Asset Status: ' || b.asset_status, NULL),
        IFF(b.trig_deactivated = 1, 'Deactivated', NULL),
        IFF(b.trig_120_holdco = 1, 'Holdco: 120+ DPD', NULL),
        IFF(b.trig_120_senior = 1, 'Senior: 120+ DPD, FICO >= 650', NULL),
        IFF(b.trig_60_senior = 1,
            IFF(b.latest_fico IS NULL, 'Senior: 60+ DPD, no FICO', 'Senior: 60+ DPD, FICO < 650'), NULL)
    ), '; ')                                             AS "Ineligible Reason",
    IFF(b.ar_agreement_number IS NULL, 1, 0)             AS "No Aging Record"

FROM base b
ORDER BY b.agreement_number;
