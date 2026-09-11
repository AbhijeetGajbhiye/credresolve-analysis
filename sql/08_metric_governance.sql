-- Metric governance: requested operational definitions using canonical event layers.
DROP TABLE IF EXISTS operational_metrics_monthly;
CREATE TABLE operational_metrics_monthly AS
WITH call_base AS (
  SELECT * FROM (
    SELECT c.*, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at, rowid) AS rn
    FROM calls c
  ) WHERE rn=1
), attempt_base AS (
  SELECT * FROM (
    SELECT ca.*, ROW_NUMBER() OVER (PARTITION BY attempt_id ORDER BY event_at, rowid) AS rn
    FROM call_attempts ca
  ) WHERE rn=1
), call_kpis AS (
  SELECT substr(a.event_at,1,7) AS month, COUNT(DISTINCT a.attempt_id) attempts,
         COUNT(DISTINCT CASE WHEN c.call_status='ANSWERED' THEN a.attempt_id END) answered
  FROM attempt_base a LEFT JOIN call_base c USING(call_id)
  GROUP BY 1
), rpc AS (
  SELECT substr(d.event_at,1,7) month, COUNT(DISTINCT d.call_id) rpc_calls
  FROM call_dispositions d JOIN call_base c USING(call_id)
  WHERE c.call_status='ANSWERED' AND d.disposition_code IN ('PTP','PROMISE_TO_PAY','PAID','CALLBACK','REFUSED','DISPUTE') GROUP BY 1
), ptp AS (
  SELECT substr(d.event_at,1,7) month, COUNT(DISTINCT d.call_id) ptp_calls
  FROM call_dispositions d JOIN call_base c USING(call_id)
  WHERE c.call_status='ANSWERED' AND d.disposition_code IN ('PTP','PROMISE_TO_PAY') GROUP BY 1
), promise_resolution AS (
  SELECT substr(promised_date,1,7) month,
         SUM(CASE WHEN status='KEPT' THEN 1 ELSE 0 END) kept,
         SUM(CASE WHEN status='BROKEN' THEN 1 ELSE 0 END) broken
  FROM promises_to_pay WHERE status IN ('KEPT','BROKEN') GROUP BY 1
), recovery AS (
  SELECT substr(event_at,1,7) month, SUM(amount) audited_cash, COUNT(DISTINCT account_id) audited_payers
  FROM golden_payments WHERE audited_recovery=1 AND payment_status='SUCCESS' GROUP BY 1
), target_accounts AS (
  SELECT DISTINCT substr(dt.target_date,1,7) month, dt.account_id, a.principal_amount
  FROM daily_targeting dt JOIN accounts a USING(account_id)
), targets AS (
  SELECT month, COUNT(*) targeted_accounts, SUM(principal_amount) targeted_principal
  FROM target_accounts GROUP BY month
), targeted_recovery AS (
  SELECT substr(gp.event_at,1,7) month, SUM(gp.amount) targeted_audited_cash, COUNT(DISTINCT gp.account_id) targeted_audited_payers
  FROM golden_payments gp JOIN target_accounts ta ON ta.month=substr(gp.event_at,1,7) AND ta.account_id=gp.account_id
  WHERE gp.audited_recovery=1 AND gp.payment_status='SUCCESS' GROUP BY 1
), hours AS (
  SELECT substr(login_at,1,7) month, SUM((julianday(logout_at)-julianday(login_at))*24.0) agent_session_hours
  FROM agent_sessions GROUP BY 1
)
SELECT c.month, c.attempts, c.answered, c.answered*1.0/NULLIF(c.attempts,0) contact_rate,
       COALESCE(r.rpc_calls,0) rpc_calls, COALESCE(r.rpc_calls,0)*1.0/NULLIF(c.answered,0) rpc_rate,
       COALESCE(p.ptp_calls,0) ptp_calls, COALESCE(p.ptp_calls,0)*1.0/NULLIF(r.rpc_calls,0) ptp_rate,
       pm.kept, pm.broken, pm.kept*1.0/NULLIF(pm.kept+pm.broken,0) ptp_kept_rate,
       rec.audited_cash, rec.audited_payers, tr.targeted_audited_cash, tr.targeted_audited_payers, t.targeted_accounts, t.targeted_principal,
       tr.targeted_audited_cash*1.0/NULLIF(t.targeted_principal,0) recovery_rate,
       tr.targeted_audited_cash*1.0/NULLIF(t.targeted_accounts,0) recovery_per_targeted_account,
       h.agent_session_hours, rec.audited_cash*1.0/NULLIF(h.agent_session_hours,0) recovery_per_agent_hour
FROM call_kpis c LEFT JOIN rpc r USING(month) LEFT JOIN ptp p USING(month)
LEFT JOIN promise_resolution pm USING(month) LEFT JOIN recovery rec USING(month)
LEFT JOIN targets t USING(month) LEFT JOIN targeted_recovery tr USING(month) LEFT JOIN hours h USING(month);

SELECT * FROM operational_metrics_monthly ORDER BY month;
