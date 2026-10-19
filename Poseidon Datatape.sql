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

       case when psd.asset_status in ('Customer Purchased System','Force Majeure (Home Damaged)', 'Removed - Permanent', 'Force Majeure (System Damaged)','Asset Impaired- Removed Permanent', 'Asset Impaired Removed-Permanent', 'Asset Impaired Pending-Removal', 'Installed, No PTO- writeoff', 'Removed (Permanent)', 'Inactive', 'Equipment Stolen', 'Asset Impaired Pending-Removal-Billable', 'Offline', 'Bankruptcy','Damage Related Removed (Insurance claim and contract terminated)','Contract Terminated - Leave In Place') then '1' else '0' end as "Ineligible Asset Status"


FROM prod_db.d_pfam.PSD_QUARTERLY_SNAPSHOT psd

LEFT JOIN prod_db.d_pfam.quarterly_default_report as def on psd.agreement_number = def.agreement_number
and def.row_num in ('1')

left join prod_db.d_pfam.abs_aging_report as ar 
    on psd.agreement_number = ar.agreement_number     
    and ar.row_num in ('1') 


    WHERE psd.TE_FUND in (
    'Balerion II 2021',
    'Jupiter Owner 2022',
    'Mercury 2021',
    'Pegasus 2021',
    'Ragnar 2021',
    'VSLR Restore Utah'

  
    
    )
