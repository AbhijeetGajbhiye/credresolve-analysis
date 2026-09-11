-- Driver analysis outputs used in the submission.
-- SQLite compatible. Assumes 01_staging_clean.sql and 02_golden_payments.sql have run.

-- 1) July priority band performance.
SELECT
    substr(target_date,1,7) AS month,
    priority,
    COUNT(DISTINCT dt.account_id) AS targeted_accounts,
    COUNT(DISTINCT CASE
        WHEN gp.account_id IS NOT NULL THEN dt.account_id END) AS paying_accounts,
    100.0 * COUNT(DISTINCT CASE
        WHEN gp.account_id IS NOT NULL THEN dt.account_id END)
        / NULLIF(COUNT(DISTINCT dt.account_id),0) AS payer_rate_pct
FROM daily_targeting dt
LEFT JOIN (
    SELECT DISTINCT account_id, substr(event_at,1,7) AS month
    FROM golden_payments
    WHERE audited_recovery=1 AND payment_status='SUCCESS'
) gp
  ON gp.account_id=dt.account_id
 AND gp.month=substr(dt.target_date,1,7)
WHERE substr(dt.target_date,1,7)='2026-07'
GROUP BY 1,2
ORDER BY priority;

-- 2) Channel 7-day conversion from targeting recommendations.
-- Targeting has a DATE but no time-of-day. To prevent same-day pre-treatment leakage,
-- the production window is the next 7 full calendar days after the targeting date;
-- the target date itself is excluded. This is intentionally conservative.
WITH target_base AS (
    SELECT DISTINCT target_id, account_id, DATE(target_date) AS target_date, recommended_channel
    FROM daily_targeting
), paid AS (
    SELECT DISTINCT account_id, DATE(event_at) AS pay_date
    FROM golden_payments
    WHERE audited_recovery=1 AND payment_status='SUCCESS'
)
SELECT
    tb.recommended_channel AS channel,
    COUNT(DISTINCT tb.target_id) AS unique_targeting_touches,
    COUNT(DISTINCT CASE WHEN p.account_id IS NOT NULL THEN tb.target_id END) AS payers_next_7d,
    100.0 * COUNT(DISTINCT CASE WHEN p.account_id IS NOT NULL THEN tb.target_id END) / NULLIF(COUNT(DISTINCT tb.target_id),0) AS conversion_next_7d_pct
FROM target_base tb
LEFT JOIN paid p
  ON p.account_id=tb.account_id
 AND p.pay_date > tb.target_date
 AND p.pay_date <= DATE(tb.target_date,'+7 day')
GROUP BY tb.recommended_channel
ORDER BY conversion_next_7d_pct DESC;

-- 3) Calling-hour performance using the call row timezone as the trusted event timezone.
SELECT
    CAST(strftime('%H', event_at) AS INTEGER) AS call_hour,
    COUNT(*) AS calls,
    AVG(CASE WHEN call_status='ANSWERED' THEN 1.0 ELSE 0.0 END) AS answer_rate,
    AVG(duration_sec) AS avg_duration_sec
FROM calls
GROUP BY 1
ORDER BY 1;

-- 4) DPD mix check for Jan versus Jul targeted portfolio.
-- Limitation: the supplied account table has a current DPD snapshot, not monthly DPD history.
-- This decomposition therefore tests current-extract DPD composition only; historical DPD at target time is unavailable.
WITH targets AS (
    SELECT DISTINCT substr(target_date,1,7) AS month, account_id
    FROM daily_targeting
    WHERE substr(target_date,1,7) IN ('2026-01','2026-07')
), buckets AS (
    SELECT
        t.month,
        CASE
          WHEN a.dpd < 30 THEN '0-29'
          WHEN a.dpd < 60 THEN '30-59'
          WHEN a.dpd < 90 THEN '60-89'
          ELSE '90+'
        END AS dpd_bucket,
        COUNT(*) AS accounts
    FROM targets t JOIN accounts a USING(account_id)
    GROUP BY 1,2
)
SELECT
    month,
    dpd_bucket,
    accounts,
    1.0 * accounts / SUM(accounts) OVER (PARTITION BY month) AS mix_share
FROM buckets
ORDER BY month, dpd_bucket;
