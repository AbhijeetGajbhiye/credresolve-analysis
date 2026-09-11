-- ============================================================================
-- 05_driver_analysis.sql
-- Part 2 "Why did it happen?" - stratified breakdowns across every required
-- dimension. Run after 02_golden_dataset.sql.
-- Interpretation / Fact-vs-Correlation labeling is done in the notebook and
-- the Data Quality / Executive reports, not here - this file only produces
-- the underlying numbers.
-- ============================================================================

-- Portfolio mix (risk_segment) x month, recovery outcome
DROP VIEW IF EXISTS driver_risk_segment;
CREATE VIEW driver_risk_segment AS
SELECT strftime('%Y-%m', p.event_at) AS month, a.risk_segment,
    COUNT(*) AS n_payments, SUM(p.amount) AS recovered
FROM golden_payments p JOIN golden_accounts a ON a.account_id = p.account_id
WHERE p.is_success = 1
GROUP BY 1, 2 ORDER BY 1, 2;

-- DPD bucket x month
DROP VIEW IF EXISTS driver_dpd_bucket;
CREATE VIEW driver_dpd_bucket AS
SELECT strftime('%Y-%m', p.event_at) AS month, a.dpd_bucket,
    COUNT(*) AS n_payments, SUM(p.amount) AS recovered
FROM golden_payments p JOIN golden_accounts a ON a.account_id = p.account_id
WHERE p.is_success = 1
GROUP BY 1, 2 ORDER BY 1, 2;

-- Loan type x month
DROP VIEW IF EXISTS driver_loan_type;
CREATE VIEW driver_loan_type AS
SELECT strftime('%Y-%m', p.event_at) AS month, a.loan_type,
    COUNT(*) AS n_payments, SUM(p.amount) AS recovered
FROM golden_payments p JOIN golden_accounts a ON a.account_id = p.account_id
WHERE p.is_success = 1
GROUP BY 1, 2 ORDER BY 1, 2;

-- Geography (borrower city/state) x month -- LOW TRUST: see DQ report,
-- borrower demographic fields are noisy/inconsistent across snapshots.
DROP VIEW IF EXISTS driver_geography;
CREATE VIEW driver_geography AS
SELECT strftime('%Y-%m', p.event_at) AS month, b.state,
    COUNT(*) AS n_payments, SUM(p.amount) AS recovered
FROM golden_payments p JOIN golden_borrowers b ON b.borrower_id = p.borrower_id
WHERE p.is_success = 1
GROUP BY 1, 2 ORDER BY 1, 2;

-- Campaign channel x month
DROP VIEW IF EXISTS driver_channel;
CREATE VIEW driver_channel AS
SELECT strftime('%Y-%m', dt.target_date) AS month, dt.recommended_channel,
    COUNT(DISTINCT dt.account_id) AS accounts_targeted,
    SUM(CASE WHEN dt.status = 'CONTACTED' THEN 1 ELSE 0 END) AS contacted
FROM golden_daily_targeting dt
GROUP BY 1, 2 ORDER BY 1, 2;

-- Telephony vendor x month (call connect rate)
DROP VIEW IF EXISTS driver_vendor;
CREATE VIEW driver_vendor AS
SELECT strftime('%Y-%m', event_at_local) AS month, vendor_id,
    COUNT(*) AS n_calls,
    SUM(CASE WHEN call_status='ANSWERED' THEN 1 ELSE 0 END) AS answered
FROM golden_calls GROUP BY 1, 2 ORDER BY 1, 2;

-- Calling hour-of-day (LOCAL time, post timezone-fix) x connect rate
DROP VIEW IF EXISTS driver_calling_hour;
CREATE VIEW driver_calling_hour AS
SELECT CAST(strftime('%H', event_at_local) AS INTEGER) AS hour_of_day,
    COUNT(*) AS n_calls,
    SUM(CASE WHEN call_status='ANSWERED' THEN 1 ELSE 0 END) AS answered,
    ROUND(100.0 * SUM(CASE WHEN call_status='ANSWERED' THEN 1 ELSE 0 END) / COUNT(*), 2) AS connect_rate_pct
FROM golden_calls GROUP BY 1 ORDER BY 1;

-- Attempt frequency vs eventual PTP/payment outcome
DROP VIEW IF EXISTS driver_attempt_frequency;
CREATE VIEW driver_attempt_frequency AS
SELECT attempt_no, COUNT(*) AS n_attempts,
    SUM(CASE WHEN attempt_status='CONNECTED' THEN 1 ELSE 0 END) AS connected,
    ROUND(100.0 * SUM(CASE WHEN attempt_status='CONNECTED' THEN 1 ELSE 0 END) / COUNT(*), 2) AS connect_rate_pct
FROM golden_call_attempts GROUP BY 1 ORDER BY 1;

-- Agent tenure (days since joined_at, from the noisy agents snapshot - directional only)
DROP VIEW IF EXISTS driver_agent_tenure;
CREATE VIEW driver_agent_tenure AS
SELECT
    CASE
        WHEN tenure_days < 90 THEN '0-90d'
        WHEN tenure_days < 180 THEN '90-180d'
        WHEN tenure_days < 365 THEN '180-365d'
        ELSE '365d+'
    END AS tenure_bucket,
    COUNT(*) AS n_calls,
    SUM(CASE WHEN c.call_status='ANSWERED' THEN 1 ELSE 0 END) AS answered
FROM golden_calls c
JOIN (
    SELECT agent_id, joined_at,
        CAST(JULIANDAY('2026-07-01') - JULIANDAY(joined_at) AS INTEGER) AS tenure_days
    FROM golden_agents
) ga ON ga.agent_id = c.agent_id
GROUP BY 1 ORDER BY 1;

-- Borrower segment (risk_segment already captured above; here by outstanding balance quartile)
DROP VIEW IF EXISTS driver_balance_quartile;
CREATE VIEW driver_balance_quartile AS
SELECT NTILE(4) OVER (ORDER BY outstanding_amount) AS balance_quartile,
    account_id, outstanding_amount
FROM golden_accounts;
