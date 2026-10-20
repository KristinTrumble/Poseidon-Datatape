-- Poseidon datatape - output lines up 1:1 with the "Data Tape" input tab (columns B:EF, header row 6),
-- same headers (line breaks in headers replaced with a space).
-- Source priority: ABS data tape (abs.) wherever it has the field; PSD quarterly snapshot (psd.) only for
-- fields the ABS tape does not carry. Formula columns reproduce the input-tab formulas; manual-input
-- columns are output as NULL (blank) for the team to populate. Diagnostics follow EF.

WITH params AS (
    SELECT
        0.005              AS degradation,          -- DG2 annual production degradation
        '2017-12-31'::date AS ma_pbi_date,          -- DJ2
        '2020-04-30'::date AS nj_pbi_date,          -- DK2
        0.9                AS renewal_pct,          -- DX2 auto renewal % of end-of-contract utility payment
        25                 AS dpd_min_balance,      -- Aging tab: a past-due bucket counts only at >= $25
        650                AS fico_floor,           -- Model Inputs Q5: Senior FICO threshold (EB / EC)
        0                  AS holdco_mode,          -- Model Inputs O3: 1 = Holdco (EA only), otherwise Senior (EB / EC)
        '2017-07-12'::date AS lease_refund_cutoff,  -- Reference C29: monthly leases signed before this date ...
        0.13               AS lease_refund_pre_rate -- Reference E29: ... use this lease refund rate
),

-- Estimated 2022 utility rate by Utility & State ('Utility Rates' tab, column I; 2021 EIA data grown 1%).
utility_rates (utility_state, rate) AS (
    SELECT * FROM VALUES
        ('APSAZ', 0.13586169193117),
        ('TEPAZ', 0.135356216373141),
        ('APUCA', 0.171377234642132),
        ('Banning Electric UtilityCA', 0.221042873667413),
        ('BurbankCA', 0.160555733917741),
        ('Colton Electric UtilityCA', 0.151201704004137),
        ('Glendale Water & PowerCA', 0.219437518447606),
        ('LADWPCA', 0.214034748200718),
        ('PasadenaCA', 0.212364654383503),
        ('PG&ECA', 0.261230915245138),
        ('Riverside Public UtilitiesCA', 0.174290203397829),
        ('Roseville ElectricCA', 0.159857427015117),
        ('UIC EnergyCT', 0.132302280840363),
        ('Gulf Power - MPHFL', 0.12018295688363),
        ('NAVFACFL', 0.12018295688363),
        ('SCEAZ', 0.221042873667413),
        ('O&RNJ', 0.163687517592585),
        ('National GridNY', 0.193480603933498),
        ('NYSE&GNY', 0.193480603933498),
        ('DelmarvaDE', 0.124436407981273),
        ('SCECA', 0.215469734400186),
        ('SDG&ECA', 0.309545647473195),
        ('Silicon Valley PowerCA', 0.132331578200561),
        ('SMUDCA', 0.163729801099025),
        ('Imperial Irrigation DistrictCA', 0.145617182795383),
        ('Lathrop Irrigation DistrictCA', 0.221042873667413),
        ('Lodi Electric Utility DepartmentCA', 0.195131917252015),
        ('Merced Irrigation DistrictCA', 0.185450923154615),
        ('Modesto Irrigation DistrictCA', 0.182274955085019),
        ('Moreno Valley Electric UtilityCA', 0.26606796533257),
        ('Turlock Irrigation DistrictCA', 0.160475185457833),
        ('XCELCO', 0.125790406175391),
        ('United PowerCO', 0.134402259337858),
        ('IREACO', 0.134402259337858),
        ('Fort Collins UtilitiesCO', 0.119779538191056),
        ('Colorado Springs UtilitiesCO', 0.134668461317883),
        ('EversourceCT', 0.2151009507481),
        ('United IlluminatingCT', 0.254455702982927),
        ('PepcoDC', 0.123068733006298),
        ('Duke EnergyFL', 0.138285004286431),
        ('OUCFL', 0.12727286081487),
        ('TECO EnergyFL', 0.117485991724127),
        ('FPLFL', 0.11344337007121),
        ('Gulf Power CoFL', 0.140421409109453),
        ('HECOHI', 0.327941415768426),
        ('HELCOHI', 0.382964549820498),
        ('MECOHI', 0.354679965042933),
        ('KIUCHI', 0.366951193058568),
        ('ComEdIL', 0.136218133172782),
        ('EversourceMA', 0.2449658639978),
        ('National GridMA', 0.251724148470031),
        ('NSTARMA', 0.2449658639978),
        ('UNITILMA', 0.256833030974938),
        ('WMECOMA', 0.2449658639978),
        ('BG&EMD', 0.12417441121115),
        ('Choptank ElectricMD', 0.139505258868553),
        ('DelmarvaMD', 0.154649763440727),
        ('PepcoMD', 0.141235502223474),
        ('Potomac EdisonMD', 0.110868238521394),
        ('SMECOMD', 0.122260444629287),
        ('EversourceNH', 0.197007242773112),
        ('UNITILNH', 0.190634024263957),
        ('ACENJ', 0.187753570798334),
        ('JCP&LNJ', 0.133266061078249),
        ('PSE&GNJ', 0.175759890553793),
        ('Rockland ElectricNJ', 0.177899149128729),
        ('RocklandNJ', 0.177899149128729),
        ('VinelandNJ', 0.166699718706048),
        ('PNMNM', 0.146597747163967),
        ('NV Energy SouthNV', 0.1173529488405),
        ('NV Energy NorthNV', 0.1173529488405),
        ('Central HudsonNY', 0.187149541855658),
        ('ConEdisonNY', 0.275985269921418),
        ('O&RNY', 0.200474300825432),
        ('PSEGLINY', 0.222939952106745),
        ('Met-EdPA', 0.128597104231708),
        ('PECOPA', 0.127240269425453),
        ('PenelecPA', 0.146721636140436),
        ('PPLPA', 0.137256450882042),
        ('PREPAPR', 0.2768),
        ('National GridRI', 0.223282027248484),
        ('Duke EnergySC', 0.112509689207986),
        ('SCE&GSC', 0.148078862456907),
        ('Duke Energy ProgressSC', 0.112509689207986),
        ('Centerpoint EnergyTX', 0.141610885379926),
        ('OncorTX', 0.147259683115294),
        ('TNMPTX', 0.122263459411056),
        ('Rocky Mountain PowerUT', 0.105350121890358),
        ('Green Mountain PowerVT', 0.197789239058855),
        ('Burlington Electric DepartmentVT', 0.163989076263655),
        ('Vermont Electric CooperativeVT', 0.197833572262473),
        ('Washington Electric Co-OpVT', 0.243402709320444)
),

-- Assumed utility rate escalator by state (model 'Utility Escalators' tab B6:C20; other states use C24).
utility_escalators (esc_state, state_escalator) AS (
    SELECT * FROM VALUES
        ('AZ', 0.040045478961577),
        ('CA', 0.043091170333832),
        ('CO', 0.044856172618651),
        ('CT', 0.026821569439874),
        ('FL', 0.035517470313863),
        ('HI', 0.023879390267745),
        ('MD', 0.030703413784796),
        ('MA', 0.025546326423182),
        ('NV', 0.039424199505464),
        ('NJ', 0.035118435067595),
        ('NM', 0.037742340759594),
        ('NY', 0.028583666050401),
        ('PA', 0.0356529496219),
        ('SC', 0.036107832118296),
        ('TX', 0.024665192894096)
),

-- Lease refund rate by Monthly/Prepaid, state and utility ('Reference' tab B33:E100).
lease_refund_rates (lr_product_type, lr_state, lr_utility, refund_rate) AS (
    SELECT * FROM VALUES
        ('Monthly', 'AZ', 'APS', 0.11),
        ('Monthly', 'AZ', 'TEP', 0.07),
        ('Monthly', 'CA', 'ALAMEDA', 0.13),
        ('Monthly', 'CA', 'APU', 0.13),
        ('Monthly', 'CA', 'BANNING ELECTRIC UTILITY', 0.13),
        ('Monthly', 'CA', 'BURBANK', 0.13),
        ('Monthly', 'CA', 'COLTON ELECTRIC UTILITY', 0.13),
        ('Monthly', 'CA', 'GLENDALE WATER & POWER', 0.13),
        ('Monthly', 'CA', 'LADWP', 0.13),
        ('Monthly', 'CA', 'LODI ELECTRIC UTILITY DEPARTMENT', 0.13),
        ('Monthly', 'CA', 'SILICON VALLEY POWER', 0.07),
        ('Monthly', 'CO', 'United Power', 0.07),
        ('Monthly', 'CO', 'Fort Collins Utilities', 0.07),
        ('Monthly', 'CO', 'XCEL', 0.07),
        ('Monthly', 'CT', 'CL&P', 0.13),
        ('Monthly', 'CT', 'EVERSOURCE', 0.13),
        ('Monthly', 'CT', 'UNITED ILLUMINATING', 0.13),
        ('Monthly', 'HI', 'HECO', 0.13),
        ('Monthly', 'HI', 'HELCO', 0.13),
        ('Monthly', 'HI', 'MECO', 0.13),
        ('Monthly', 'IL', 'ComEd', 0.07),
        ('Monthly', 'NH', 'EVERSOURCE', 0.13),
        ('Monthly', 'NH', 'PSCNH', 0.13),
        ('Monthly', 'NH', 'UNITIL', 0.13),
        ('Monthly', 'NY', 'CONEDISON', 0.13),
        ('Monthly', 'NY', 'LIPA', 0.13),
        ('Monthly', 'NY', 'O&R', 0.13),
        ('Monthly', 'NY', 'PSEGLI', 0.13),
        ('Monthly', 'NY', 'CENTRAL HUDSON', 0.11),
        ('Monthly', 'NY', 'NATIONAL GRID', 0.07),
        ('Monthly', 'NY', 'NYSE&G', 0.07),
        ('Monthly', 'SC', 'SCE&G', 0.11),
        ('Monthly', 'SC', 'DUKE ENERGY', 0.07),
        ('Monthly', 'SC', 'DUKE ENERGY PROGRESS', 0.07),
        ('Prepaid', 'AZ', 'APS', 0.05),
        ('Prepaid', 'AZ', 'TEP', 0.05),
        ('Prepaid', 'CA', 'LODI ELECTRIC UTILITY DEPARTMENT', 0.1),
        ('Prepaid', 'CA', 'ALAMEDA', 0.1),
        ('Prepaid', 'CA', 'APU', 0.1),
        ('Prepaid', 'CA', 'BURBANK', 0.08),
        ('Prepaid', 'CA', 'BANNING ELECTRIC UTILITY', 0.08),
        ('Prepaid', 'CA', 'COLTON ELECTRIC UTILITY', 0.08),
        ('Prepaid', 'CA', 'GLENDALE WATER & POWER', 0.08),
        ('Prepaid', 'CA', 'LADWP', 0.08),
        ('Prepaid', 'CA', 'Merced Irrigation District', 0.08),
        ('Prepaid', 'CA', 'SILICON VALLEY POWER', 0.05),
        ('Prepaid', 'CA', 'IMPERIAL IRRIGATION DISTRICT', 0.08),
        ('Prepaid', 'CO', 'United Power', 0.07),
        ('Prepaid', 'CO', 'XCEL', 0.08),
        ('Prepaid', 'CT', 'EVERSOURCE', 0.1),
        ('Prepaid', 'CT', 'UNITED ILLUMINATING', 0.08),
        ('Prepaid', 'CT', 'CL&P', 0.08),
        ('Prepaid', 'HI', 'HECO', 0.13),
        ('Prepaid', 'HI', 'HELCO', 0.13),
        ('Prepaid', 'HI', 'MECO', 0.13),
        ('Prepaid', 'IL', 'ComEd', 0.04),
        ('Prepaid', 'NH', 'EVERSOURCE', 0.13),
        ('Prepaid', 'NH', 'PSCNH', 0.08),
        ('Prepaid', 'NY', 'NYSE&G', 0.1),
        ('Prepaid', 'NY', 'O&R', 0.1),
        ('Prepaid', 'NY', 'PSEGLI', 0.1),
        ('Prepaid', 'NY', 'CONEDISON', 0.1),
        ('Prepaid', 'NY', 'UNITIL', 0.1),
        ('Prepaid', 'NY', 'CENTRAL HUDSON', 0.08),
        ('Prepaid', 'NY', 'LIPA', 0.08),
        ('Prepaid', 'NY', 'NATIONAL GRID', 0.08),
        ('Prepaid', 'SC', 'SCE&G', 0.08),
        ('Prepaid', 'SC', 'DUKE ENERGY', 0.05)
),

-- Battery adder used when a battery system has no battery payment (model 'Battery Monthly Payment' tab
-- defaults, by state; other states have none and use 0).
battery_adder_defaults (bd_state, adder) AS (
    SELECT * FROM VALUES
        ('CA', 0.618986159085),
        ('NJ', 0.341032368692),
        ('FL', 0.175398228318),
        ('IL', 0.079788970348),
        ('PR', 0.065454545455),
        ('MA', 0.053750813172)
),

base AS (
    SELECT
        -- ABS data tape fields
        abs.agreement_number, abs.te_fund, abs.state, abs.city, abs.utility_clean,
        abs.pbi_level, abs.pbi_term, abs."Install Date", abs.system_size, abs.est_yr1_gen_contract,
        abs."Price per kwh", abs.base_lease_payment_amount, abs.escalator, abs.upfront_including_deposit,
        abs.asset_status, abs."Year 1 Monthly Payment", abs.install_partner, abs.transfer_price,
        abs.panel_vendor_clean, abs.inverter_vendor_clean, abs.battery_vendor_clean, abs.battery_model_clean,
        abs.battery_count, abs."String or Micro", abs.fico_latest_service_transfer_score,
        -- Balanced vs Generation (CA, CB, CZ) comes from the PSD billing type, as in the model (BZ).
        IFF(psd.billing_type = 'Generation', 'Generation', 'Balanced') AS "Contract Type",
        abs."ACH (Y/N)", abs."Sunrun Originated Asset", abs."Multifamily Project?", abs."Expected PTO Date",
        abs."Months Since PTO at EOQ", abs."Contract Months Remaining", abs."First Payment Date",
        abs."Last Payment Date", abs."Termporary Removal Check", abs."Terminated Solar Asset Flag (a.)",
        abs.escalator_flag, abs."FLAG Implied $/kWh Rate", abs."FLAG Year 1 Monthly Payment",
        abs.battery_data_error_flag, abs.billing_method, abs."% of Contracted Gen Guaranteed",
        v.*,
        psd.agreement_number AS psd_agreement_number,
        psd.te_fund AS psd_te_fund,

        -- Fields not on the ABS data tape (from PSD)
        IFF(psd.sc_brightbox_flag, 1, 0) AS sc_brightbox_flag,                              -- C: TRUE = 1, FALSE / blank = 0
        psd.county,
        psd.address,
        psd.asset_sale_date,
        psd.pto_date,
        psd.upfront_payment_amount,
        psd.initial_deposit_amount,
        psd.estimated_rebate_amount,
        psd.avoided_cost_of_power,
        psd.sr_signoff,
        psd.billing_type,
        psd.pegu_s,
        psd.proposal_name,
        psd.sales_channel,
        psd.battery_capacity,
        psd.base_battery_payment,
        COALESCE(psd.FICO_SERVICE_TRANSFER_FLAG::int, 0) AS st_flag,                        -- AY
        COALESCE(psd.previous_quarter_service_transfer_flag::int, 0) AS qtr_st_flag,        -- AZ
        CASE WHEN psd.asset_status IN ('Customer Purchased System','Force Majeure (Home Damaged)', 'Removed - Permanent', 'Force Majeure (System Damaged)','Asset Impaired- Removed Permanent', 'Asset Impaired Removed-Permanent', 'Asset Impaired Pending-Removal', 'Installed, No PTO- writeoff', 'Removed (Permanent)', 'Inactive', 'Equipment Stolen', 'Asset Impaired Pending-Removal-Billable', 'Offline', 'Bankruptcy','Damage Related Removed (Insurance claim and contract terminated)','Contract Terminated - Leave In Place') THEN 1 ELSE 0 END AS prior_list_ineligible_status,

        def."total_write_offs",
        def."Deactivation Default Flag",
        def."Aging Default Flag",
        ar.agreement_number AS ar_agreement_number,
        ar."ABS Aging Bucket",
        ar."Current Balance", ar."1-30 Days Past Due", ar."31-60 Days Past Due", ar."61-90 Days Past Due",
        ar."91-120 Days Past Due", ar."121-180 Days Past Due", ar."181-360 Days Past Due", ar."361+ Days Past Due",
        ar."Outstanding Balance",
        pegu.pegu_payout_frequency,

        abs.agreement_term_years AS term_years,                                                       -- CD
        abs."Product Type" AS product_type,                                                           -- BY (Monthly / Prepaid)
        -- BX: ABS "Product"; when blank, from the PSD billing type (Lease -> Lease, otherwise PPA)
        COALESCE(NULLIF(abs."Product", ''), IFF(psd.billing_type = 'Lease', 'Lease', 'PPA')) AS ppa_or_lease,
        CASE WHEN psd.billing_type = 'Fixed monthly PPA with annual reset' THEN 'Balanced' ELSE psd.billing_type END AS billing_type_based_on_proposal, -- BZ
        IFF(UPPER(TO_VARCHAR(abs."Ineligible Asset Status")) IN ('1','Y','YES','TRUE'), 1, 0) AS ineligible_asset_status, -- ED

        -- Aging flags (Aging tab): a bucket counts when its balance is >= dpd_min_balance ($25).
        COALESCE(ar."31-60 Days Past Due",0) + COALESCE(ar."61-90 Days Past Due",0) + COALESCE(ar."91-120 Days Past Due",0)
          + COALESCE(ar."121-180 Days Past Due",0) + COALESCE(ar."181-360 Days Past Due",0) + COALESCE(ar."361+ Days Past Due",0) AS bal_31,
        bal_31 - COALESCE(ar."31-60 Days Past Due",0)  AS bal_61,
        bal_61 - COALESCE(ar."61-90 Days Past Due",0)  AS bal_91,
        bal_91 - COALESCE(ar."91-120 Days Past Due",0) AS bal_121,
        IFF(COALESCE(ar."Current Balance",0) <> 0, 1, 0)    AS dpd_0_flag,
        IFF(COALESCE(ar."1-30 Days Past Due",0) <> 0, 1, 0) AS dpd_1_30_flag,
        IFF(bal_31  >= v.dpd_min_balance, 1, 0) AS dpd_30_flag,
        IFF(bal_61  >= v.dpd_min_balance, 1, 0) AS dpd_60_flag,
        IFF(bal_91  >= v.dpd_min_balance, 1, 0) AS dpd_90_flag,
        IFF(bal_121 >= v.dpd_min_balance, 1, 0) AS dpd_120_flag,
        IFF(COALESCE(ar."361+ Days Past Due", 0) >= v.dpd_min_balance, 1, 0) AS dpd_361_flag,
        COALESCE(def."Aging Default Flag", 0) AS aging_default_flag,

        -- FICO (BD) = ABS "Adjusted FICO". 'Not Available' plays the model's "No Score"; 'Military Housing' its "MPH".
        abs."Adjusted FICO" AS fico,
        TRY_TO_NUMBER(fico) AS fico_num,
        (fico = 'Not Available') AS no_fico,

        -- Contract detail
        -- CV: ABS implied rate; when blank, the model formula (Prepaid 0, Generation = price, else payment x 12 / kWh)
        COALESCE(abs."Implied $/kWh Rate",
                 CASE WHEN product_type = 'Prepaid' THEN 0
                      WHEN billing_type_based_on_proposal = 'Generation' THEN abs."Price per kwh"
                      ELSE COALESCE(abs.base_lease_payment_amount, abs."Year 1 Monthly Payment") * 12 / NULLIF(abs.est_yr1_gen_contract, 0) END) AS implied_rate,
        -- CW: battery payment x 12 / year-1 kWh; battery systems without a payment use the state default.
        CASE WHEN COALESCE(psd.base_battery_payment, 0) * 12 / NULLIF(abs.est_yr1_gen_contract, 0) > 0
                 THEN psd.base_battery_payment * 12 / abs.est_yr1_gen_contract
             WHEN COALESCE(abs.battery_count, 0) > 0 THEN COALESCE(bd.adder, 0)
             ELSE 0 END AS battery_adder,
        implied_rate * abs.est_yr1_gen_contract AS year_1_revenue,                                    -- CY
        CASE WHEN abs.escalator = 0 THEN 0
             WHEN product_type = 'Prepaid' THEN 0
             WHEN ppa_or_lease = 'Lease' OR billing_type_based_on_proposal = 'Balanced'
                  THEN (1 + abs.escalator) / (1 - v.degradation) - 1
             ELSE abs.escalator END AS implied_escalator,                                             -- DG
        COALESCE(abs."Contract Months Remaining", term_years * 12) / 12 AS contracted_years_remaining,  -- DT (full term if not yet PTO)
        urt.rate AS utility_rate,                                                                     -- DQ
        COALESCE(esc.state_escalator, 0.036455143875545) AS utility_escalator,                              -- DS
        -- DA: lease refund rate (Reference tab logic)
        CASE WHEN ppa_or_lease = 'PPA' OR abs.state IN ('FL', 'HI', 'PR') THEN 0
             WHEN abs.state = 'UT'
                  THEN COALESCE(abs.upfront_including_deposit, 0)
                       / NULLIF(abs.est_yr1_gen_contract * (1 - POWER(1.005, -term_years)) / 0.005 * 1.005, 0)
                       + implied_rate
             WHEN abs.te_fund = 'Kina 2019' THEN implied_rate
             WHEN psd.sr_signoff IS NOT NULL AND psd.sr_signoff::date < v.lease_refund_cutoff THEN v.lease_refund_pre_rate
             ELSE COALESCE(NULLIF(lr.refund_rate, 0), implied_rate) END AS lease_refund_rate,

        -- Eligibility triggers (1 = trigger hit), following the model. Each asset is counted under its first
        -- trigger only: ED only when EB/EC are 0, EE only when EB:ED are 0.
        IFF(v.holdco_mode = 1, dpd_120_flag, 0) AS trig_120_holdco,                                   -- EA
        IFF(v.holdco_mode = 1, 0,
            IFF(dpd_361_flag = 1 AND (fico_num >= v.fico_floor OR fico = 'Military Housing'), 1, 0)) AS trig_120_senior, -- EB: 361+ >= $25
        IFF(v.holdco_mode = 1, 0,
            IFF(dpd_60_flag = 1 AND (fico_num < v.fico_floor OR no_fico), 1, 0)) AS trig_60_senior,   -- EC
        IFF(trig_120_senior + trig_60_senior > 0, 0, ineligible_asset_status) AS trig_ineligible_status, -- ED
        IFF(trig_120_senior + trig_60_senior + trig_ineligible_status > 0, 0,
            IFF(UPPER(TO_VARCHAR(def."Deactivation Default Flag")) IN ('1','Y','YES','TRUE'), 1, 0)) AS trig_deactivated -- EE

    -- PSD drives the row set so every Poseidon agreement appears even if the ABS tape is missing it
    -- (see "No ABS Record" diagnostic).
    FROM prod_db.d_pfam.PSD_QUARTERLY_SNAPSHOT psd

    LEFT JOIN prod_db.d_pfam.abs_data_tape AS abs
        ON psd.agreement_number = abs.agreement_number

    LEFT JOIN prod_db.d_pfam.quarterly_default_report AS def
        ON psd.agreement_number = def.agreement_number
        AND def.row_num IN ('1')

    LEFT JOIN prod_db.d_pfam.abs_aging_report AS ar
        ON psd.agreement_number = ar.agreement_number
        AND ar.row_num IN ('1')

    -- Pegu payout frequency is set at contract start, so it is frozen from the current tape
    -- (see "Poseidon Pegu Payout Frequency.sql" for the one-time load).
    LEFT JOIN prod_db.d_pfam.poseidon_pegu_payout_frequency AS pegu
        ON psd.agreement_number = pegu.agreement_number

    CROSS JOIN params v

    LEFT JOIN utility_rates AS urt
        ON urt.utility_state = abs.utility_clean || abs.state

    LEFT JOIN utility_escalators AS esc
        ON esc.esc_state = abs.state

    LEFT JOIN lease_refund_rates AS lr
        ON lr.lr_product_type = abs."Product Type" AND lr.lr_state = abs.state AND UPPER(lr.lr_utility) = UPPER(abs.utility_clean)

    LEFT JOIN battery_adder_defaults AS bd
        ON bd.bd_state = abs.state

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
    b.psd_agreement_number                               AS "Agreement Number",                         -- B
    b.sc_brightbox_flag                                  AS "BrightBox",                                -- C  psd
    b.state                                              AS "State",                                    -- D
    b.city                                               AS "City",                                     -- E
    b.county                                             AS "Customer Address",                         -- F  psd (input tab holds county here)
    b.address                                            AS "Zip Code",                                 -- G  psd (input tab holds full address here)
    b.utility_clean                                      AS "Utility Company",                          -- H
    -- Jupiter Owner 2022 is split by PTO vintage (matches the "Jupiter TE Fund Fixes" tab: 2,535 / 3,745)
    CASE WHEN b.psd_te_fund = 'Jupiter Owner 2022'
         THEN 'Jupiter Owner 2022 ' || IFF(YEAR(b.pto_date) <= 2013, '[2012 - 2013]', '[2014 - 2017]')
         ELSE b.psd_te_fund END                          AS "TE Fund Name",                             -- I
    b.asset_sale_date                                    AS "In TE Fund",                               -- J  psd
    b.pbi_level                                          AS "PBI Rate $/kWh",                           -- K
    b.pbi_term                                           AS "PBI Term",                                 -- L
    b."Install Date"                                     AS "Install Date",                             -- M
    b.pto_date                                           AS "Actual PTO Date",                          -- N  psd (ABS has expected/actual only)
    b.system_size                                        AS "System Size DC",                           -- O
    b.est_yr1_gen_contract                               AS "Est Yr 1 Generation",                      -- P
    b."Price per kwh"                                    AS "Price per kWh",                            -- Q
    b.base_lease_payment_amount                          AS "Monthly Base Payment",                     -- R
    b.escalator                                          AS "Annual Monthly Payment Escalator",         -- S
    b.term_years * 12                                    AS "Agreement Term (Months)",                  -- T
    b.upfront_payment_amount                             AS "Upfront Payment",                          -- U  psd (ABS only has upfront incl. deposit)
    b.initial_deposit_amount                             AS "Deposit",                                  -- V  psd
    b.estimated_rebate_amount                            AS "Rebate",                                   -- W  psd
    b.avoided_cost_of_power                              AS "Year 1 Avoided Cost of Power",             -- X  psd
    b.sr_signoff                                         AS "SR Signoff",                               -- Y  psd
    b.billing_method                                     AS "Billing Method",                           -- Z
    b.billing_type                                       AS "Billing Type",                             -- AA psd
    b.asset_status                                       AS "Asset Status",                             -- AB
    b.pegu_s                                             AS "Pegu Start Year",                          -- AC psd
    b.proposal_name                                      AS "Proposal: Proposal ID",                    -- AD psd
    b."Year 1 Monthly Payment"                           AS "Year 1 Monthly Payment",                   -- AE
    b.install_partner                                    AS "Installer",                                -- AF
    b.transfer_price                                     AS "FMV",                                      -- AG
    b.sales_channel                                      AS "Acquisition Channel",                      -- AH psd
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
    b.battery_capacity                                   AS "Battery Capacity kWh [CLEAN]",             -- AT psd
    CASE WHEN b.battery_model_clean = 'RESU 10H Prime' THEN 'RESU 10H Prime'
         WHEN COALESCE(b.battery_model_clean, '0') IN ('0', '') THEN '-'
         ELSE 'Other' END                                AS "RESU 10H Prime vs. Other",                 -- AU
    b."String or Micro"                                  AS "String or Micro",                          -- AV
    NULL                                                 AS " ",                                        -- AW
    NULL                                                 AS " ",                                        -- AX
    b.st_flag                                            AS "ST FLAG (All Time)",                       -- AY psd
    b.qtr_st_flag                                        AS "Current QTR ST (to be built out in future)", -- AZ psd
    NULL                                                 AS "Transunion FICO pulls",                    -- BA (team populates)
    b.fico_latest_service_transfer_score                 AS "Current FICO SNF Model",                   -- BB
    NULL                                                 AS "Prior Quarter DT FICO",                        -- BC (team populates)
    b.fico                                               AS "FICO",                                     -- BD
    CASE WHEN b.pto_date IS NOT NULL THEN 'PTO'
         WHEN b."Install Date" IS NOT NULL THEN 'Install'
         ELSE 'PreInstall' END                           AS "Facility Status",                          -- BE
    NULL                                                 AS "X",                                        -- BF
    TRY_TO_NUMBER(REPLACE(b."% of Contracted Gen Guaranteed", '%', ''), 10, 4) / 100
                                                         AS "Production Guarantee %",                   -- BG
    b.pegu_payout_frequency                              AS "Pegu Payout Frequency",                    -- BH frozen lookup
    NULL                                                 AS "X",                                        -- BI
    b.dpd_0_flag                                         AS "0+ Days Past Due (1=Yes, 0=No)",           -- BJ
    b.dpd_1_30_flag                                      AS "1-30 Days Past Due (1=Yes, 0=No)",         -- BK
    b.dpd_30_flag                                        AS "30+ Days Past Due (1=Yes, 0=No)",          -- BL
    b.dpd_60_flag                                        AS "60+ Days Past Due (1=Yes, 0=No)",          -- BM
    b.dpd_90_flag                                        AS "90+ Days Past Due (1=Yes, 0=No)",          -- BN
    b.dpd_120_flag                                       AS "120 Days Past Due (1=Yes, 0=No)",          -- BO
    b."Aging Default Flag"                               AS "Aging Default Flag",                       -- BP
    NULL                                                 AS "X",                                        -- BQ
    b.utility_clean || b.state                           AS "Utility&State",                            -- BR
    b.utility_clean                                      AS "Utility Corrected",                        -- BS
    CASE WHEN b.state = 'CA' AND b.utility_clean IN ('SCE','PG&E','SDG&E') THEN 'IOU'
         WHEN b.state = 'CA' THEN 'Muni' END             AS "California Utility Code",                  -- BT
    CASE WHEN b.state <> 'CA' THEN b.state
         WHEN b.utility_clean IN ('PG&E','SCE','SDG&E') THEN 'CA-' || b.utility_clean
         ELSE 'CA-Muni' END                              AS "CA-IOU vs. CA-Muni",                       -- BU
    NULL                                                 AS "x",                                        -- BV
    RIGHT(b.proposal_name, 1)                            AS "Proposal Code",                            -- BW
    b.ppa_or_lease                                       AS "PPA or Lease",                             -- BX
    b.product_type                                       AS "Monthly Or Prepaid",                       -- BY
    b.billing_type_based_on_proposal                     AS "Billing Type Based on Proposal",           -- BZ
    IFF(b."Contract Type" = 'Generation', 'Generation', 'Balanced')
                                                         AS "Balanced or Generation (PPA Type)",        -- CA
    IFF(b.product_type = 'Monthly' AND b.ppa_or_lease = 'PPA' AND b."Contract Type" = 'Generation'
        AND b.term_years IN (20, 25), 'Generation Billing', NULL)
                                                         AS "Billing Type",                             -- CB
    b.product_type || ' ' || TO_VARCHAR(b.term_years::int) || ' Year '
        || IFF(b.product_type = 'Monthly' AND b.ppa_or_lease = 'PPA',
               "Balanced or Generation (PPA Type)" || ' ', '')
        || b.ppa_or_lease                                AS "Product Code",                             -- CC
    b.term_years                                         AS "Agreement Term (Years)",                   -- CD
    IFF(b.sc_brightbox_flag >= 1, 'Brightbox', 'Standard') AS "Brightbox",                              -- CE
    IFF(UPPER(b."ACH (Y/N)") IN ('Y', 'YES'), 'Yes', 'No') AS "ACH",                                    -- CF
    b."Sunrun Originated Asset"                          AS "Sunrun Originated Asset (Y/N)",            -- CG
    IFF(UPPER(TO_VARCHAR(b."Multifamily Project?")) IN ('1','Y','YES','TRUE'), 'Yes', 'No')
                                                         AS "Multifamily",                              -- CH
    b.sales_channel                                      AS "Current Channel",                          -- CI psd
    IFF(b.fico = 'Military Housing', 1, 0)               AS "Military Housing (1=Yes; 0=No)",           -- CJ
    NULL                                                 AS "X",                                        -- CK
    LAST_DAY(b."Expected PTO Date", 'quarter')           AS "PTO Quarter",                              -- CL
    b."Expected PTO Date"                                AS "Actual & Estimated PTO Date",              -- CM
    YEAR(b."Expected PTO Date")                          AS "PTO Year",                                 -- CN
    b."Months Since PTO at EOQ"                          AS "Months Since PTO",                         -- CO
    b.contracted_years_remaining * 12                    AS "Remaining Time Contracted (Months)",       -- CP
    b."First Payment Date"                               AS "First Payment Date (Expected if No PTO)",  -- CQ
    b."Last Payment Date"                                AS "Last Payment Date (Expected if No PTO)",   -- CR
    IFF(b.pto_date IS NULL, 'No PTO', 'PTO')             AS "Actually Achieve PTO Yet?",                -- CS
    IFF(b.pto_date IS NULL, 'No PTO', 'PTO')             AS "Estimated PTO Check (at Initial Closing)", -- CT
    NULL                                                 AS "X",                                        -- CU
    b.implied_rate                                       AS "Implied $/kWh Rate (For both PPAs and Leases)", -- CV
    b.battery_adder                                      AS "Battery Adder ($/kWh)",                    -- CW
    b.implied_rate - b.battery_adder                     AS "Solar Only Rate ($/kWh)",                  -- CX
    b.year_1_revenue                                     AS "Year 1 Revenue",                           -- CY
    CASE WHEN b.product_type = 'Prepaid' THEN 0
         WHEN b."Contract Type" = 'Generation'
              THEN b.year_1_revenue * (((b.implied_rate * (1 + b.escalator) * b.est_yr1_gen_contract * (1 - b.degradation)) / NULLIF(b.year_1_revenue, 0)) - 1)
         ELSE b.year_1_revenue * b.escalator END         AS "Year 1 Escalator ($)",                     -- CZ
    b.lease_refund_rate                                  AS "Lease Refund Rate",                        -- DA
    IFF(b.ppa_or_lease = 'PPA',
        -- (Upfront + Deposit) / -PV(0.5%, years, gen, 0, 1) + implied rate
        COALESCE(b.upfront_including_deposit, 0)
          / NULLIF(b.est_yr1_gen_contract * (1 - POWER(1.005, -b.term_years)) / 0.005 * 1.005, 0)
          + b.implied_rate,
        0)                                               AS "PPA Refund Rate",                          -- DB
    (b.lease_refund_rate + "PPA Refund Rate") * b.est_yr1_gen_contract
                                                         AS "Year 1 Refund Rate * kWh Production",      -- DC
    b.year_1_revenue * b.escalator                       AS "Year 1 Revenue * Escalator",               -- DD
    b.est_yr1_gen_contract * b.pbi_level                 AS "Est 1st Year Production * PBI $ / kWh",    -- DE
    b.term_years * b.system_size                         AS "Contract Years * kW",                      -- DF
    b.implied_escalator                                  AS "Implied $/kWh Escalator",                  -- DG
    b.transfer_price / NULLIF(b.system_size, 0) / 1000   AS "FMV ($/W)",                                -- DH
    IFF(b.state = 'IL', 0, b.pbi_level)                  AS "PBI Rate ($/kWh)",                         -- DI
    IFF(b.state = 'MA' AND b."Expected PTO Date" > b.ma_pbi_date, 1, 0) AS "MA PBI Flag",               -- DJ
    IFF(b.state = 'NJ' AND b."Expected PTO Date" > b.nj_pbi_date, 1, 0) AS "NJ PBI Flag",               -- DK
    -- EOMONTH(PTO, term months) as an Excel date serial * kW
    DATEDIFF(day, '1899-12-30'::date, LAST_DAY(DATEADD(month, b.term_years * 12, b."Expected PTO Date"))) * b.system_size
                                                         AS "Contracted Period End Date*kW",            -- DL
    NULL                                                 AS "X",                                        -- DM
    IFF(b.product_type = 'Monthly', b.implied_rate * POWER(1 + b.implied_escalator, b.term_years), 0)
                                                         AS "End of Contracted Rate",                   -- DN
    b.est_yr1_gen_contract * POWER(1 - b.degradation, b.term_years)
                                                         AS "Implied End of Contracted Period Production (Contract)", -- DO
    "Implied End of Contracted Period Production (Contract)" * "End of Contracted Rate"
                                                         AS "End of Contract Payments",                 -- DP
    b.utility_rate                                       AS "Estimated 2022 Utility Rate ($/kWh)",      -- DQ
    b.utility_rate * b.est_yr1_gen_contract * POWER(1 - b.degradation, b.term_years - b.contracted_years_remaining)
                                                         AS "2022 Utility Rate * 2022 Contracted Production", -- DR
    b.utility_escalator                                  AS "Assumed Utility Rate Escalator",           -- DS
    b.contracted_years_remaining                         AS "Contracted Years Remaining",               -- DT
    b.utility_rate * POWER(1 + b.utility_escalator, b.contracted_years_remaining)
                                                         AS "Implied End of Contract Utility Rate",     -- DU
    "Implied End of Contract Utility Rate" * b.est_yr1_gen_contract * POWER(1 - b.degradation, b.term_years)
                                                         AS "Implied End of Contract Utility Payment",  -- DV
    b.contracted_years_remaining * b.utility_escalator   AS "PA Consulting Escalator * Contracted Years Remaining", -- DW
    "Implied End of Contract Utility Rate" * b.renewal_pct * "Implied End of Contracted Period Production (Contract)"
                                                         AS "Auto Renewal Annual Payment",              -- DX
    NULL                                                 AS "x",                                        -- DY
    NULL                                                 AS "Prior Quarter PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- DZ (team populates)
    b.trig_120_holdco                                    AS "120+ dpd (Holdco only)",                   -- EA
    b.trig_120_senior                                    AS "120+ dpd (361+ not resolved) and FICO =>650 (Senior only)", -- EB
    b.trig_60_senior                                     AS "60+ dpd and No FICO or FICO <650 (Senior only)", -- EC
    b.trig_ineligible_status                             AS "Ineligible Asset Status",                  -- ED
    b.trig_deactivated                                   AS "Deactivated",                              -- EE
    NULL                                                 AS "Current Quarter PMT Date Eligible Projects (1=Eligible, 0=Ineligible)", -- EF (team calculates: depends on prior eligibility in DZ)

    -- Aging data (right of EF, outside the model range) to check against the DPD flags and triggers
    b."Current Balance"                                  AS "Current Balance",
    b."1-30 Days Past Due"                               AS "1-30 Days Past Due",
    b."31-60 Days Past Due"                              AS "31-60 Days Past Due",
    b."61-90 Days Past Due"                              AS "61-90 Days Past Due",
    b."91-120 Days Past Due"                             AS "91-120 Days Past Due",
    b."121-180 Days Past Due"                            AS "121-180 Days Past Due",
    b."181-360 Days Past Due"                            AS "181-360 Days Past Due",
    b."361+ Days Past Due"                               AS "361+ Days Past Due",
    b."Outstanding Balance"                              AS "Outstanding Balance",
    NULL                                                 AS "x",
    b."ABS Aging Bucket"                                 AS "ABS Aging Bucket",
    NULL                                                 AS "x",

    -- Diagnostics
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
        IFF(b.trig_120_senior = 1, 'Senior: 361+ DPD >= $25, FICO >= 650 or Military Housing', NULL),
        IFF(b.trig_60_senior = 1,
            IFF(b.no_fico, 'Senior: 60+ DPD, no FICO (' || COALESCE(b.fico, 'blank') || ')', 'Senior: 60+ DPD, FICO < 650'), NULL),
        IFF(b.trig_ineligible_status = 1, 'Asset Status: ' || b.asset_status, NULL),
        IFF(b.trig_deactivated = 1, 'Deactivated', NULL),
        IFF(b.trig_120_holdco = 1, 'Holdco: 120+ DPD', NULL)
    ), '; ')                                             AS "Ineligible Reason",
    b.prior_list_ineligible_status                       AS "Ineligible Asset Status (prior hardcoded list)",
    b.ineligible_asset_status                            AS "Ineligible Asset Status (ABS flag, before waterfall)",
    b."Termporary Removal Check"                         AS "ABS Temporary Removal Check",
    b."Terminated Solar Asset Flag (a.)"                 AS "ABS Terminated Solar Asset Flag (a.)",
    b.escalator_flag                                     AS "ABS Escalator Flag",
    b."FLAG Implied $/kWh Rate"                          AS "ABS FLAG Implied $/kWh Rate",
    b."FLAG Year 1 Monthly Payment"                      AS "ABS FLAG Year 1 Monthly Payment",
    b.battery_data_error_flag                            AS "ABS Battery Data Error Flag",
    IFF(b.agreement_number IS NULL, 1, 0)                AS "No ABS Record",
    IFF(b.ar_agreement_number IS NULL, 1, 0)             AS "No Aging Record"

FROM base b
ORDER BY b.psd_agreement_number;
