-- Canonical payment audit: dedupe by payment_id BEFORE reference ambiguity checks.
DROP TABLE IF EXISTS payment_dedup;
CREATE TABLE payment_dedup AS
SELECT * FROM (
  SELECT p.*, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at, rowid) AS rn
  FROM payments p
) WHERE rn=1;

DROP TABLE IF EXISTS payment_ref_stats;
CREATE TABLE payment_ref_stats AS
SELECT payment_reference, COUNT(DISTINCT account_id) AS ref_accounts, COUNT(DISTINCT amount) AS ref_amounts, COUNT(*) AS ref_rows
FROM payment_dedup WHERE TRIM(COALESCE(payment_reference,''))<>'' GROUP BY payment_reference;

DROP TABLE IF EXISTS golden_payments;
CREATE TABLE golden_payments AS
SELECT d.payment_id, d.account_id, d.borrower_id, d.event_at, d.payment_reference, d.amount,
       d.payment_status, d.payment_method, d.provider_id,
       CASE WHEN d.payment_status='SUCCESS'
             AND (TRIM(COALESCE(d.payment_reference,''))=''
                  OR (COALESCE(s.ref_accounts,0)=1 AND COALESCE(s.ref_amounts,0)=1))
            THEN 1 ELSE 0 END AS audited_recovery
FROM payment_dedup d
LEFT JOIN payment_ref_stats s USING(payment_reference);

DROP TABLE IF EXISTS rejected_payments;
CREATE TABLE rejected_payments AS
SELECT *, CASE WHEN payment_status<>'SUCCESS' THEN 'NON_SUCCESS_STATUS'
               WHEN TRIM(COALESCE(payment_reference,''))='' THEN 'SUCCESS_WITH_BLANK_REFERENCE'
               ELSE 'AMBIGUOUS_REFERENCE' END AS rejection_reason
FROM golden_payments WHERE audited_recovery=0;
