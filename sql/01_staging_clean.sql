-- SQLite-compatible staging/clean layer
-- Assumes CSVs have been imported as tables with their filenames sans extension.

DROP TABLE IF EXISTS stg_accounts;
CREATE TABLE stg_accounts AS
SELECT *, CASE WHEN borrower_id IS NULL OR TRIM(borrower_id)='' THEN 1 ELSE 0 END AS missing_borrower_id
FROM accounts;

DROP TABLE IF EXISTS stg_calls;
CREATE TABLE stg_calls AS
SELECT *,
  DATE(event_at) AS event_date,
  CASE WHEN timezone IS NULL OR TRIM(timezone)='' THEN 1 ELSE 0 END AS missing_timezone
FROM calls;

DROP TABLE IF EXISTS stg_payments;
CREATE TABLE stg_payments AS
SELECT *,
  ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at, rowid) AS payment_id_rn
FROM payments;

DROP TABLE IF EXISTS stg_status;
CREATE TABLE stg_status AS
SELECT *, CASE WHEN recorded_at < event_at THEN 1 ELSE 0 END AS timestamp_conflict
FROM account_status_history;
