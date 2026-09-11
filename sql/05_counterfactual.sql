-- Counterfactual / experiment design.
-- The legacy full-month July payer outcome is retained only as a diagnostic; it is not causally identified.
-- Production identification must align treatment and outcome in time.
DROP TABLE IF EXISTS july_first_target;
CREATE TABLE july_first_target AS
SELECT account_id, MIN(target_date) AS first_target_date
FROM daily_targeting
WHERE substr(target_date,1,7)='2026-07'
GROUP BY account_id;

DROP TABLE IF EXISTS july_target_timing_audit;
CREATE TABLE july_target_timing_audit AS
SELECT a.account_id, a.first_target_date,
       MAX(CASE WHEN p.event_at>=datetime(a.first_target_date,'-7 day')
                 AND p.event_at < a.first_target_date THEN 1 ELSE 0 END) AS pre7_payer,
       MAX(CASE WHEN p.event_at > a.first_target_date
                 AND p.event_at <= datetime(a.first_target_date,'+7 day') THEN 1 ELSE 0 END) AS post7_payer
FROM july_first_target a
LEFT JOIN golden_payments p ON p.account_id=a.account_id AND p.audited_recovery=1 AND p.payment_status='SUCCESS'
GROUP BY a.account_id, a.first_target_date;

SELECT
  AVG(pre7_payer)*100.0 AS pre7_payer_rate_pct,
  AVG(post7_payer)*100.0 AS post7_payer_rate_pct,
  (AVG(post7_payer)-AVG(pre7_payer))*100.0 AS timing_aligned_lift_pp
FROM july_target_timing_audit;

-- Preferred production identification: randomize a 5-10% holdout among eligible accounts
-- within DPD x risk_segment x loan_type strata, with treatment assigned before the outcome window.
-- Primary statistical endpoint: 30-day payer rate. Financial decision metric: 30-day audited cash per eligible account.
-- Guardrails: 60/90-day PTP kept, complaints, contact rate, and spillover.
