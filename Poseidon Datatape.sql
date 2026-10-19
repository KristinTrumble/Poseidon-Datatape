-- Inputs for the derived model columns appended at the end of the SELECT.
WITH params AS (
    SELECT
        '2023-12-31'::date AS cutoff_date,      -- as-of date for "Months Since PTO" (reproduces the current model)
        0                  AS dpd_min_balance,  -- a DPD bucket counts as past due only above this balance ($)
        600                AS fico_floor        -- "60+ dpd and No FICO or FICO < X" threshold - confirm against model
)

SELECT

psd.agreement_number,
sc_brightbox_flag,
psd.state,
psd.city,
psd.county,
psd.address,
psd.zip_code,
psd.utility,
psd.asset_sale_date,
psd.te_fund,
psd.pbi_level,
psd.pbi_term,
psd.install_date,
psd.pto_date,
psd.system_size,
psd.est_yr1_gen_contract,
psd.price_per_kwh,
psd.base_lease_payment_amount,
psd.escalator,
psd.agreement_term_years,
psd.upfront_payment_amount,
psd.initial_deposit_amount,
psd.estimated_rebate_amount,
psd.avoided_cost_of_power,
to_varchar(psd.sr_signoff,'mm/dd/yyyy HH24:MM:SS') as "SR Signoff",
psd.billing_method,
psd.billing_type,
psd.asset_status,
psd.pegu_s,
psd.pg_threshold,
psd.proposal_name,
psd.year_1_monthly_payment,
psd.install_partner,
psd.transfer_price,
psd.sales_channel,
psd.panel_vendor_clean,
psd.inverter_vendor_clean,
psd.battery_vendor_clean,
psd.battery_model_clean,
psd.battery_count,
psd.base_battery_payment,
psd.FICO_SERVICE_TRANSFER_FLAG,
psd.FICO_LATEST_SERVICE_TRANSFER_SCORE,
psd.previous_quarter_service_transfer_flag,
ppc_contract_type,
psd.inverter_count,

CASE when psd.billing_type in ('Full Upfront') THEN 'Prepaid' ELSE 'Monthly' end as "Product Type",
case when "Product Type" in ('Prepaid') then 'Prepaid' when "Product Type" in ('Monthly') and psd.billing_method in ('Recurring') then 'Y' else 'N' end as "ACH (Y/N)",


Case when psd.billing_type = ('Fixed monthly PPA with annual reset') THEN ('Balanced')ELSE psd.billing_type End AS "Billing Type Based on Proposal",

def."days_deactivated",
def."open_reactivation_case",
def."total_write_offs",
def."Status Default Flag",
def."Deactivation Default Flag",
def."Aging Default Flag",
def."Defaulted: Three Prong Default Test",

--Aging Data

    ar."Current Balance",
    ar."1-30 Days Past Due",
    ar."31-60 Days Past Due",
    ar."61-90 Days Past Due",
    ar."91-120 Days Past Due",
    ar."121-180 Days Past Due",
    ar."181-360 Days Past Due",
    (ar."121-180 Days Past Due" + ar."181-360 Days Past Due" + ar."361+ Days Past Due") as "121+ Days Past Due",
    (ar."121-180 Days Past Due" + ar."181-360 Days Past Due" + ar."361+ Days Past Due" + ar."61-90 Days Past Due" + ar."31-60 Days Past Due" +  ar."1-30 Days Past Due" + ar."91-120 Days Past Due" +  ar."Current Balance") as "Grand Total",
    ar."361+ Days Past Due",
    ar."181-360 Days Past Due",

       case when psd.asset_status in ('Customer Purchased System','Force Majeure (Home Damaged)', 'Removed - Permanent', 'Force Majeure (System Damaged)','Asset Impaired- Removed Permanent', 'Asset Impaired Removed-Permanent', 'Asset Impaired Pending-Removal', 'Installed, No PTO- writeoff', 'Removed (Permanent)', 'Inactive', 'Equipment Stolen', 'Asset Impaired Pending-Removal-Billable', 'Offline', 'Bankruptcy','Damage Related Removed (Insurance claim and contract terminated)','Contract Terminated - Leave In Place') then '1' else '0' end as "Ineligible Asset Status",

-- =====================================================================================
-- Derived model columns (appended only - everything above keeps its position so the
-- model input page paste range is unchanged). Names follow the model headers.
-- Aging buckets are COALESCEd to 0 so an account with no aging-report row reads as
-- current instead of NULL.
-- =====================================================================================

--Past-due balances (helpers for the DPD flags)
    (COALESCE(ar."31-60 Days Past Due",0) + COALESCE(ar."61-90 Days Past Due",0) + COALESCE(ar."91-120 Days Past Due",0)
     + COALESCE(ar."121-180 Days Past Due",0) + COALESCE(ar."181-360 Days Past Due",0) + COALESCE(ar."361+ Days Past Due",0)) as "31+ DPD Balance",
    ("31+ DPD Balance" - COALESCE(ar."31-60 Days Past Due",0)) as "61+ DPD Balance",
    ("61+ DPD Balance" - COALESCE(ar."61-90 Days Past Due",0)) as "91+ DPD Balance",
    ("91+ DPD Balance" - COALESCE(ar."91-120 Days Past Due",0)) as "121+ DPD Balance",
    IFF(ar.agreement_number IS NULL, 1, 0) as "No Aging Record",

--DPD flags (model BI:BN)
    1 as "0+ Days Past Due (1=Yes)",
    IFF(COALESCE(ar."1-30 Days Past Due",0) > v.dpd_min_balance AND "31+ DPD Balance" <= v.dpd_min_balance, 1, 0) as "1-30 Days Past Due (1=Yes)",
    IFF("31+ DPD Balance" > v.dpd_min_balance, 1, 0) as "30+ Days Past Due (1=Yes)",
    IFF("61+ DPD Balance" > v.dpd_min_balance, 1, 0) as "60+ Days Past Due (1=Yes)",
    IFF("91+ DPD Balance" > v.dpd_min_balance, 1, 0) as "90+ Days Past Due (1=Yes)",
    IFF("121+ DPD Balance" > v.dpd_min_balance, 1, 0) as "120+ Days Past Due (1=Yes)",

--Utility (model BQ:BT)
    psd.utility || psd.state as "Utility&State",
    CASE WHEN psd.state <> 'CA' THEN NULL
         WHEN psd.utility IN ('PG&E','SCE','SDG&E') THEN 'IOU'
         ELSE 'Muni' END as "California Utility Code",
    CASE WHEN psd.state <> 'CA' THEN psd.state
         WHEN "California Utility Code" = 'IOU' THEN 'CA-' || psd.utility
         ELSE 'CA-Muni' END as "CA-IOU vs. CA-Muni",

--Product (model BV:CH)
    SPLIT_PART(psd.proposal_name, '-', -1) as "Proposal Code",
    IFF(psd.billing_type = 'Lease', 'Lease', 'PPA') as "PPA or Lease",
    "Product Type" as "Monthly Or Prepaid",
    IFF(psd.billing_type = 'Generation', 'Generation', 'Balanced') as "Balanced or Generation",
    IFF(psd.billing_type = 'Generation', 'Generation Billing', NULL) as "Generation Billing Type",
    "Product Type" || ' ' || TO_VARCHAR(psd.agreement_term_years::int) || ' Year ' || "Billing Type Based on Proposal" as "Product Code",
    psd.agreement_term_years as "Agreement Term (Years)",
    IFF(sc_brightbox_flag = 1, 'Brightbox', 'Standard') as "Brightbox",
    IFF(psd.billing_method = 'Recurring', 'Yes', 'No') as "ACH",
    psd.sales_channel as "Current Channel",

--PTO / term (model CK:CR)
    LAST_DAY(psd.pto_date, 'quarter') as "PTO Quarter",
    YEAR(psd.pto_date) as "PTO Year",
    ROUND(DATEDIFF(day, psd.pto_date, v.cutoff_date) / (365/12), 2) as "Months Since PTO",
    ROUND(psd.agreement_term_years * 12 - "Months Since PTO") as "Remaining Time Contracted (Months)",
    DATEADD(month, 2, psd.pto_date) as "First Payment Date (Expected)",
    DATEADD(year, psd.agreement_term_years, "First Payment Date (Expected)") as "Last Payment Date (Expected)",
    IFF(psd.pto_date IS NOT NULL, 'PTO', 'No PTO') as "Actually Achieve PTO Yet?",

--Equipment (model AT:AU)
    CASE WHEN COALESCE(psd.battery_count,0) = 0 THEN '-'
         WHEN psd.battery_model_clean = 'RESU 10H Prime' THEN 'RESU 10H Prime'
         ELSE 'Other' END as "RESU 10H Prime vs. Other",
    IFF(psd.inverter_vendor_clean ILIKE '%Enphase%', 'Micro Inverter', 'String Inverter') as "String or Micro",

--Economics (model CU:DI)
    IFF(psd.billing_type = 'Lease', psd.base_lease_payment_amount * 12, psd.price_per_kwh * psd.est_yr1_gen_contract) as "Year 1 Revenue",
    "Year 1 Revenue" * psd.escalator as "Year 1 Escalator ($)",
    "Year 1 Revenue" / NULLIF(psd.est_yr1_gen_contract,0) as "Implied $/kWh Rate",
    COALESCE(psd.base_battery_payment,0) * 12 / NULLIF(psd.est_yr1_gen_contract,0) as "Battery Adder ($/kWh)",
    "Implied $/kWh Rate" - "Battery Adder ($/kWh)" as "Solar Only Rate ($/kWh)",
    psd.agreement_term_years * psd.system_size as "Contract Years * kW",
    psd.transfer_price / NULLIF(psd.system_size * 1000, 0) as "FMV ($/W)",
    NULLIF(psd.pbi_level, 0) as "PBI Rate ($/kWh)",
    IFF(psd.state = 'MA', 1, 0) as "MA PBI Flag",
    IFF(psd.state = 'NJ', 1, 0) as "NJ PBI Flag",

--Eligibility triggers (model DZ:EE). 1 = trigger hit.
    "120+ Days Past Due (1=Yes)" as "120+ dpd (Holdco only)",
    IFF(COALESCE(ar."361+ Days Past Due",0) > v.dpd_min_balance, 1, 0) as "120+ dpd (361+ not resolved)",
    IFF("60+ Days Past Due (1=Yes)" = 1
        AND (psd.FICO_LATEST_SERVICE_TRANSFER_SCORE IS NULL OR psd.FICO_LATEST_SERVICE_TRANSFER_SCORE < v.fico_floor), 1, 0) as "60+ dpd and No FICO or FICO < Floor",
    "Ineligible Asset Status"::int as "Ineligible Asset Status (Trigger)",
    IFF(UPPER(TO_VARCHAR(def."Deactivation Default Flag")) IN ('1','Y','YES','TRUE'), 1, 0) as "Deactivated",
    IFF("120+ dpd (Holdco only)" + "120+ dpd (361+ not resolved)" + "60+ dpd and No FICO or FICO < Floor"
        + "Ineligible Asset Status (Trigger)" + "Deactivated" = 0, 1, 0) as "Current PMT Date Eligible",

-- Which trigger(s) made the asset ineligible - for reconciling ineligible counts.
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
        IFF("Ineligible Asset Status (Trigger)" = 1, 'Asset Status: ' || psd.asset_status, NULL),
        IFF("120+ dpd (Holdco only)" = 1, '120+ DPD', NULL),
        IFF("120+ dpd (361+ not resolved)" = 1, '361+ DPD', NULL),
        IFF("60+ dpd and No FICO or FICO < Floor" = 1,
            IFF(psd.FICO_LATEST_SERVICE_TRANSFER_SCORE IS NULL, '60+ DPD, no FICO', '60+ DPD, FICO < floor'), NULL),
        IFF("Deactivated" = 1, 'Deactivated', NULL)
    ), '; ') as "Ineligible Reason"


FROM prod_db.d_pfam.PSD_QUARTERLY_SNAPSHOT psd

LEFT JOIN prod_db.d_pfam.quarterly_default_report as def on psd.agreement_number = def.agreement_number
and def.row_num in ('1')

left join prod_db.d_pfam.abs_aging_report as ar 
    on psd.agreement_number = ar.agreement_number     
    and ar.row_num in ('1')

CROSS JOIN params v

    WHERE psd.TE_FUND in (
    'Balerion II 2021',
    'Jupiter Owner 2022',
    'Mercury 2021',
    'Pegasus 2021',
    'Ragnar 2021',
    'VSLR Restore Utah'

  
    
    )
