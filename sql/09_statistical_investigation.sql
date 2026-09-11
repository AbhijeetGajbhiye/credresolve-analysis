-- Statistical investigation support tables.
DROP TABLE IF EXISTS denominator_audit;
CREATE TABLE denominator_audit AS
SELECT substr(dt.target_date,1,7) month,
       (SELECT COUNT(DISTINCT account_id) FROM accounts) all_accounts_master,
       COUNT(DISTINCT dt.account_id) targeted_accounts,
       (SELECT COUNT(DISTINCT gp.account_id) FROM golden_payments gp WHERE gp.audited_recovery=1 AND gp.payment_status='SUCCESS' AND substr(gp.event_at,1,7)=substr(dt.target_date,1,7)) audited_payers
FROM daily_targeting dt GROUP BY 1;

DROP TABLE IF EXISTS cohort_effects;
CREATE TABLE cohort_effects AS
SELECT substr(dt.target_date,1,7) month,
       CASE WHEN julianday(dt.target_date)-julianday(a.opened_at)<=90 THEN '0-90'
            WHEN julianday(dt.target_date)-julianday(a.opened_at)<=180 THEN '91-180'
            WHEN julianday(dt.target_date)-julianday(a.opened_at)<=365 THEN '181-365' ELSE '366+' END age_bucket,
       COUNT(DISTINCT dt.account_id) accounts,
       COUNT(DISTINCT CASE WHEN gp.account_id IS NOT NULL THEN dt.account_id END) payers
FROM daily_targeting dt JOIN accounts a USING(account_id)
LEFT JOIN (SELECT DISTINCT account_id, substr(event_at,1,7) month FROM golden_payments WHERE audited_recovery=1 AND payment_status='SUCCESS') gp
  ON gp.account_id=dt.account_id AND gp.month=substr(dt.target_date,1,7)
WHERE substr(dt.target_date,1,7) IN ('2026-01','2026-07')
GROUP BY 1,2;

SELECT * FROM denominator_audit ORDER BY month;
SELECT * FROM cohort_effects ORDER BY month, age_bucket;

-- Common-cohort view: only account-age cohorts observed in both January and July are compared.
DROP TABLE IF EXISTS cohort_effects_common;
CREATE TABLE cohort_effects_common AS
WITH base AS (
  SELECT substr(dt.target_date,1,7) AS month,
         CASE WHEN julianday(dt.target_date)-julianday(a.opened_at)<=90 THEN '0-90'
              WHEN julianday(dt.target_date)-julianday(a.opened_at)<=180 THEN '91-180'
              WHEN julianday(dt.target_date)-julianday(a.opened_at)<=365 THEN '181-365' ELSE '366+' END age_bucket,
         dt.account_id
  FROM daily_targeting dt JOIN accounts a USING(account_id)
  WHERE substr(dt.target_date,1,7) IN ('2026-01','2026-07')
), common AS (
  SELECT age_bucket FROM base GROUP BY age_bucket HAVING COUNT(DISTINCT month)=2
)
SELECT b.month, b.age_bucket, COUNT(DISTINCT b.account_id) AS accounts,
       COUNT(DISTINCT CASE WHEN gp.account_id IS NOT NULL THEN b.account_id END) AS payers
FROM base b JOIN common c USING(age_bucket)
LEFT JOIN (SELECT DISTINCT account_id, substr(event_at,1,7) month FROM golden_payments WHERE audited_recovery=1 AND payment_status='SUCCESS') gp
  ON gp.account_id=b.account_id AND gp.month=b.month
GROUP BY b.month,b.age_bucket;

SELECT * FROM cohort_effects_common ORDER BY month, age_bucket;
