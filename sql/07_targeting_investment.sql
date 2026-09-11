-- Time-safe targeting/investment inputs.
-- Do not use the legacy cross-sectional full-month payer outcome as causal lift.
DROP TABLE IF EXISTS july_targeting_frame;
CREATE TABLE july_targeting_frame AS
WITH july_targets AS (
    SELECT account_id, MIN(target_date) AS first_target_date
    FROM daily_targeting
    WHERE substr(target_date,1,7)='2026-07'
    GROUP BY account_id
)
SELECT a.account_id, a.loan_type, a.principal_amount, a.outstanding_amount, a.dpd, a.risk_segment,
       jt.first_target_date, CASE WHEN jt.account_id IS NULL THEN 0 ELSE 1 END AS treated
FROM accounts a LEFT JOIN july_targets jt USING(account_id);

-- Addressable opportunities are account-month opportunities, not distinct accounts.
SELECT substr(target_date,1,7) AS month, COUNT(DISTINCT account_id) AS unique_target_account_opportunities
FROM daily_targeting GROUP BY 1 ORDER BY 1;

WITH monthly AS (
  SELECT substr(target_date,1,7) AS month, COUNT(DISTINCT account_id) AS opportunities
  FROM daily_targeting GROUP BY 1
)
SELECT SUM(opportunities) AS target_account_months_observed, COUNT(*) AS observed_targeting_months,
       12.0/COUNT(*) AS annualization_factor, SUM(opportunities)*12.0/COUNT(*) AS annualized_target_account_opportunities
FROM monthly;

-- Break-even hurdle: budget / (annualized targeted account-month opportunities x
-- average audited recovery per payer among targeted July accounts).
-- This is a planning hurdle only; it is not a causal historical forecast.
