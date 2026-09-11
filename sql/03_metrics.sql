-- ============================================================================
-- 03_metrics.sql
-- Monthly performance metrics, built on the golden layer.
-- Answers: "what happened" and "is the reported 11% real".
-- Run after 02_golden_dataset.sql.
-- ============================================================================

-- ---- A. THE HEADLINE COMPARISON: naive (as-reported) vs day-normalized ----
DROP VIEW IF EXISTS metric_naive_vs_normalized;
CREATE VIEW metric_naive_vs_normalized AS
WITH monthly AS (
    SELECT
        strftime('%Y-%m', event_at) AS month,
        SUM(amount) AS recovery_amount_raw_incl_duplicates,
        (SELECT SUM(amount) FROM golden_payments gp
         WHERE gp.is_success = 1 AND strftime('%Y-%m', gp.event_at) = strftime('%Y-%m', p.event_at)) AS recovery_amount_golden
    FROM raw_payments p
    WHERE payment_status = 'SUCCESS'
    GROUP BY 1
),
with_days AS (
    SELECT *,
        CAST(strftime('%d', date(month || '-01', '+1 month', '-1 day')) AS INTEGER) AS calendar_days_in_month,
        CASE WHEN month = (SELECT MAX(strftime('%Y-%m', event_at)) FROM raw_payments) THEN 1 ELSE 0 END AS is_partial_month
    FROM monthly
),
final AS (
    SELECT *,
        -- the last month in the feed is a partial month (data cut off mid-month,
        -- not a real short month) - normalize by actual days observed, not the
        -- calendar length, or exclude it from trend comparisons entirely.
        CASE WHEN is_partial_month = 1
             THEN CAST(strftime('%d', (SELECT MAX(event_at) FROM raw_payments)) AS INTEGER)
             ELSE calendar_days_in_month END AS days_in_month
    FROM with_days
)
SELECT
    month,
    days_in_month,
    is_partial_month,
    recovery_amount_raw_incl_duplicates,
    recovery_amount_golden,
    recovery_amount_golden / days_in_month AS recovery_per_day_golden,
    ROUND(100.0 * (recovery_amount_raw_incl_duplicates
        - LAG(recovery_amount_raw_incl_duplicates) OVER (ORDER BY month))
        / LAG(recovery_amount_raw_incl_duplicates) OVER (ORDER BY month), 2) AS mom_pct_raw_asreported,
    ROUND(100.0 * (recovery_amount_golden / days_in_month
        - LAG(recovery_amount_golden / days_in_month) OVER (ORDER BY month))
        / LAG(recovery_amount_golden / days_in_month) OVER (ORDER BY month), 2) AS mom_pct_per_day_true
FROM final
ORDER BY month;

-- ---- B. Full monthly metrics panel ----
DROP VIEW IF EXISTS metric_monthly_panel;
CREATE VIEW metric_monthly_panel AS
WITH months AS (
    SELECT DISTINCT strftime('%Y-%m', target_date) AS month FROM golden_daily_targeting
),
targeted AS (
    SELECT strftime('%Y-%m', target_date) AS month, COUNT(DISTINCT account_id) AS targeted_accounts
    FROM golden_daily_targeting GROUP BY 1
),
calls_agg AS (
    SELECT strftime('%Y-%m', event_at_local) AS month,
        COUNT(*) AS total_outbound_calls,
        SUM(CASE WHEN call_status='ANSWERED' THEN 1 ELSE 0 END) AS answered_calls
    FROM golden_calls GROUP BY 1
),
disp_agg AS (
    SELECT strftime('%Y-%m', event_at) AS month,
        COUNT(*) AS total_dispositions,
        SUM(CASE WHEN disposition_code NOT IN ('WRONG_NUMBER','NO_CONTACT') THEN 1 ELSE 0 END) AS rpc_dispositions
    FROM golden_call_dispositions GROUP BY 1
),
ptp_agg AS (
    SELECT strftime('%Y-%m', event_at) AS month,
        COUNT(*) AS ptps_created,
        SUM(CASE WHEN status='KEPT' THEN 1 ELSE 0 END) AS ptps_kept,
        SUM(CASE WHEN status='BROKEN' THEN 1 ELSE 0 END) AS ptps_broken
    FROM golden_promises_to_pay GROUP BY 1
),
pay_agg AS (
    SELECT strftime('%Y-%m', event_at) AS month,
        SUM(amount) AS recovery_amount
    FROM golden_payments WHERE is_success = 1 GROUP BY 1
),
hours_agg AS (
    SELECT strftime('%Y-%m', login_at) AS month, SUM(session_hours) AS agent_hours
    FROM golden_agent_sessions GROUP BY 1
)
SELECT
    m.month,
    t.targeted_accounts,
    ROUND(100.0 * c.answered_calls / NULLIF(c.total_outbound_calls,0), 2) AS contact_rate_pct,
    ROUND(100.0 * d.rpc_dispositions / NULLIF(d.total_dispositions,0), 2) AS rpc_rate_pct,
    ROUND(100.0 * pt.ptps_created / NULLIF(d.rpc_dispositions,0), 2) AS ptp_rate_pct,
    ROUND(100.0 * pt.ptps_kept / NULLIF(pt.ptps_kept + pt.ptps_broken, 0), 2) AS ptp_kept_rate_pct,
    ROUND(pay.recovery_amount, 0) AS recovery_amount,
    ROUND(pay.recovery_amount / NULLIF(t.targeted_accounts,0), 0) AS recovery_per_account,
    ROUND(pay.recovery_amount / NULLIF(h.agent_hours,0), 2) AS recovery_per_agent_hour
FROM months m
LEFT JOIN targeted t ON t.month = m.month
LEFT JOIN calls_agg c ON c.month = m.month
LEFT JOIN disp_agg d ON d.month = m.month
LEFT JOIN ptp_agg pt ON pt.month = m.month
LEFT JOIN pay_agg pay ON pay.month = m.month
LEFT JOIN hours_agg h ON h.month = m.month
ORDER BY m.month;

-- ---- C. Channel conversion (last-touch attribution, 14-day window) ----
-- NOTE: see 04_forensics.sql for the attribution-bias sensitivity check
-- (last-touch vs multi-touch) that justifies using last-touch here.
DROP VIEW IF EXISTS metric_channel_conversion;
CREATE VIEW metric_channel_conversion AS
WITH touches AS (
    SELECT account_id, event_at AS touch_at, 'VOICE' AS channel FROM golden_calls
    UNION ALL
    SELECT account_id, event_at, 'WHATSAPP' FROM golden_whatsapp_events
    UNION ALL
    SELECT account_id, event_at, 'SMS' FROM golden_sms_events
    UNION ALL
    SELECT account_id, event_at, 'FIELD' FROM golden_field_visits
),
paid AS (
    SELECT account_id, event_at AS paid_at, amount FROM golden_payments WHERE is_success = 1
),
last_touch AS (
    SELECT p.account_id, p.paid_at, p.amount,
        (SELECT t.channel FROM touches t
         WHERE t.account_id = p.account_id AND t.touch_at <= p.paid_at
           AND t.touch_at >= datetime(p.paid_at, '-14 days')
         ORDER BY t.touch_at DESC LIMIT 1) AS credited_channel
    FROM paid p
)
SELECT credited_channel AS channel, COUNT(*) AS payments_credited, SUM(amount) AS amount_credited
FROM last_touch
WHERE credited_channel IS NOT NULL
GROUP BY 1
ORDER BY amount_credited DESC;
