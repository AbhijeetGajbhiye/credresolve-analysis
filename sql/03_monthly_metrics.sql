-- Monthly recovery metrics using business event month.
WITH gp AS (
  SELECT account_id, substr(event_at,1,7) AS month, SUM(amount) AS cash, COUNT(DISTINCT account_id) AS paying_accounts
  FROM golden_payments
  WHERE audited_recovery=1
  GROUP BY account_id, month
), targets AS (
  SELECT DISTINCT account_id, substr(target_date,1,7) AS month
  FROM daily_targeting
), target_principal AS (
  SELECT t.month, SUM(a.principal_amount) AS principal, COUNT(DISTINCT t.account_id) AS targeted_accounts
  FROM targets t JOIN accounts a USING(account_id)
  GROUP BY t.month
), monthly AS (
  SELECT month, SUM(cash) AS audited_cash, SUM(CASE WHEN (account_id,month) IN (SELECT account_id,month FROM targets) THEN cash ELSE 0 END) AS targeted_cash
  FROM gp GROUP BY month
)
SELECT m.month, m.audited_cash, m.targeted_cash, p.principal AS targeted_principal, p.targeted_accounts,
       CASE WHEN p.principal>0 THEN m.targeted_cash/p.principal ELSE NULL END AS targeted_recovery_yield
FROM monthly m LEFT JOIN target_principal p USING(month) ORDER BY m.month;
