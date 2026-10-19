-- One-time load: freeze Pegu Payout Frequency from the current Poseidon tape.
-- The frequency is set at the start of the contract and never changes, so later tapes read it
-- from this table instead of re-entering it (joined in "Poseidon Datatape.sql").
--
-- 1. Create the table (change the schema if you don't have write access to d_pfam).
CREATE TABLE IF NOT EXISTS prod_db.d_pfam.poseidon_pegu_payout_frequency (
    agreement_number      VARCHAR,
    pegu_payout_frequency VARCHAR   -- 'Annual' / 'Biennial' / 'NA'
);

-- 2. Load the two columns from the current tape (Agreement Number, Pegu Payout Frequency):
--    Snowsight > Data > prod_db.d_pfam > poseidon_pegu_payout_frequency > Load Data, upload a CSV
--    with those two columns (header row on). Or paste rows into an INSERT:
-- INSERT INTO prod_db.d_pfam.poseidon_pegu_payout_frequency (agreement_number, pegu_payout_frequency) VALUES
--     ('1124148256', 'Biennial'),
--     ('1123653075', 'Annual');

-- 3. Check: one row per agreement.
SELECT COUNT(*) AS row_count, COUNT(DISTINCT agreement_number) AS agreements
FROM prod_db.d_pfam.poseidon_pegu_payout_frequency;
