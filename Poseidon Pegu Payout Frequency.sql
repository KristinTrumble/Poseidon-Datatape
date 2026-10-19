-- One-time load: freeze Pegu Payout Frequency from the current Poseidon tape.
-- The frequency is set at the start of the contract and never changes, so later tapes read it
-- from this table instead of re-entering it (joined in "Poseidon Datatape.sql").
-- Source: "Poseidon PeGu Frequency" tab of "Poseidon DT for Model", exported to
-- poseidon_pegu_payout_frequency.csv in this repo (48,421 agreements, one row each).
--
-- 1. Create the table (change the schema here and in "Poseidon Datatape.sql" if you don't have
--    write access to d_pfam).
CREATE TABLE IF NOT EXISTS prod_db.d_pfam.poseidon_pegu_payout_frequency (
    agreement_number      VARCHAR,
    pegu_payout_frequency VARCHAR   -- 'Annual' / 'Biennial' / 'NA'
);

-- 2. Load poseidon_pegu_payout_frequency.csv:
--    Snowsight > Data > Databases > PROD_DB > D_PFAM > POSEIDON_PEGU_PAYOUT_FREQUENCY > Load Data,
--    upload the CSV, file format CSV with "Skip first line" (header) on.

-- 3. Check: 48,421 rows, one per agreement.
SELECT COUNT(*) AS row_count, COUNT(DISTINCT agreement_number) AS agreements
FROM prod_db.d_pfam.poseidon_pegu_payout_frequency;

SELECT pegu_payout_frequency, COUNT(*) FROM prod_db.d_pfam.poseidon_pegu_payout_frequency GROUP BY 1 ORDER BY 2 DESC;
-- Expected: Biennial 29,084 / NA 12,060 / Annual 7,256 / 0% 21
