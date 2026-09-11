-- ============================================================================
-- 04_forensics.sql
-- Part 2 Data Forensics (A-G from the assignment brief), as runnable queries
-- against the RAW tables (forensics must look at raw data, not golden).
-- ============================================================================

-- A. DUPLICATE PAYMENTS -------------------------------------------------
-- Exact full-row duplicates
SELECT 'A1_exact_duplicate_payment_rows' AS check_name,
    COUNT(*) - COUNT(DISTINCT payment_id || event_at || amount || payment_status) AS flagged_rows
FROM raw_payments;

-- Duplicate payment_id with possibly different attributes
SELECT 'A2_duplicate_payment_id' AS check_name, payment_id, COUNT(*) AS n
FROM raw_payments GROUP BY payment_id HAVING COUNT(*) > 1;

-- Same account + amount within 60 minutes, different payment_id (retry signature)
SELECT 'A3_near_duplicate_retry_signature' AS check_name, COUNT(*) AS flagged_rows
FROM (
    SELECT p1.payment_id
    FROM raw_payments p1
    JOIN raw_payments p2
      ON p1.account_id = p2.account_id
     AND p1.amount = p2.amount
     AND p1.payment_id <> p2.payment_id
     AND ABS(strftime('%s', p1.event_at) - strftime('%s', p2.event_at)) < 3600
);
-- Finding: after removing A1/A2 exact/id duplicates, A3 nets to ~0 on this dataset -
-- i.e. the "duplicate payment" problem here IS the exact/id-duplicate issue, not a
-- separate retry-with-new-id pattern. Quantified impact: 500 of 25,500 raw rows
-- (~1.96%) were dupes; SUCCESS-status amount overstated by ~2% before cleaning.

-- B. ATTRIBUTION ERRORS --------------------------------------------------
-- Payments have NO campaign_id / interaction_id column at all - attribution must
-- be derived. Check: what % of successful payments have ANY recorded touch
-- (call/WA/SMS/field) in the 14 days before payment? Low coverage = attribution
-- is fragile regardless of method chosen.
SELECT 'B1_payments_with_no_prior_touch_14d' AS check_name,
    COUNT(*) AS successful_payments,
    SUM(CASE WHEN touch_count = 0 THEN 1 ELSE 0 END) AS payments_with_no_touch,
    ROUND(100.0 * SUM(CASE WHEN touch_count = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_unattributable
FROM (
    SELECT p.payment_id,
        (SELECT COUNT(*) FROM (
            SELECT account_id, event_at FROM raw_calls
            UNION ALL SELECT account_id, event_at FROM raw_whatsapp_events
            UNION ALL SELECT account_id, event_at FROM raw_sms_events
            UNION ALL SELECT account_id, event_at FROM raw_field_visits
        ) t WHERE t.account_id = p.account_id
              AND t.event_at <= p.event_at
              AND t.event_at >= datetime(p.event_at, '-14 days')
        ) AS touch_count
    FROM raw_payments p WHERE p.payment_status = 'SUCCESS'
);
-- See notebook for the last-touch vs multi-touch credit-split comparison
-- (Python; window-function fan-out is impractical at full scale in pure SQL).
-- Result: last-touch and split-credit attribution agree within ~1pp per channel
-- on this dataset - i.e., no material last-touch bias detected - but ~64% of
-- successful payments have no recorded touch within 14 days, so channel-level
-- conversion/ROI numbers carry real uncertainty regardless of attribution method.

-- C. TIMEZONE PROBLEMS ----------------------------------------------------
SELECT 'C1_timezone_mix_by_table' AS check_name, 'accounts' AS tbl, timezone, COUNT(*) AS n FROM raw_accounts GROUP BY timezone
UNION ALL
SELECT 'C1_timezone_mix_by_table', 'calls', timezone, COUNT(*) FROM raw_calls GROUP BY timezone
UNION ALL
SELECT 'C1_timezone_mix_by_table', 'agent_sessions', timezone, COUNT(*) FROM raw_agent_sessions GROUP BY timezone;
-- Finding: calls/accounts/sessions are recorded in three different timezones
-- (UTC, Asia/Kolkata, Asia/Dubai) with no normalization in the raw feed. Any
-- hour-of-day or day-boundary analysis (e.g. "best calling time") done on raw
-- event_at without converting to a single zone will misclassify a meaningful
-- share of records near midnight. Golden layer normalizes to UTC (see
-- 01_staging / build_golden_dataset.py) while retaining local time for
-- calling-time-of-day analysis.

-- D. VENDOR MAPPING CHANGES -----------------------------------------------
SELECT 'D1_vendor_schema_versions' AS check_name, schema_version, COUNT(*) AS n
FROM raw_vendor_telephony GROUP BY schema_version;

SELECT 'D2_disposition_code_by_version' AS check_name, disposition_version, disposition_code, COUNT(*) AS n
FROM raw_call_dispositions GROUP BY disposition_version, disposition_code
ORDER BY disposition_version, disposition_code;
-- Finding: 'PTP' and 'PROMISE_TO_PAY' are the same disposition recorded under two
-- code strings, present across ALL disposition_version values equally (~3,926
-- rows) - this is a code inconsistency independent of the version field, not a
-- clean "legacy vs new" cutover. Canonicalized in golden layer.

-- E. AGENT IDENTITY PROBLEMS -----------------------------------------------
SELECT 'E1_rows_per_agent_id' AS check_name,
    COUNT(DISTINCT agent_id) AS distinct_agent_ids,
    COUNT(*) AS total_rows,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT agent_id), 1) AS avg_rows_per_agent
FROM raw_agents;

SELECT 'E2_employee_codes_per_agent_id' AS check_name,
    agent_id, COUNT(DISTINCT employee_code) AS distinct_employee_codes
FROM raw_agents GROUP BY agent_id
HAVING COUNT(DISTINCT employee_code) > 1
LIMIT 10;
-- Finding: ALL 1,000 agent_ids show >1 employee_code/vendor_id/team/name across
-- their raw snapshot rows (14-48 rows each). employee_code is unusable as an
-- identity key here; agent_id is the only stable key (and the one every fact
-- table actually references).

-- F. PORTFOLIO MIX CHANGES -------------------------------------------------
SELECT 'F1_monthly_risk_segment_mix' AS check_name,
    strftime('%Y-%m', dt.target_date) AS month, a.risk_segment, COUNT(DISTINCT dt.account_id) AS n
FROM raw_daily_targeting dt JOIN raw_accounts a ON a.account_id = dt.account_id
GROUP BY 1, 2 ORDER BY 1, 2;
-- Finding: risk_segment / dpd_bucket / loan_type / account_status mix among
-- targeted accounts is flat (~25% each category) in every month - no genuine
-- portfolio mix shift detected over the observed window.

-- G. DENOMINATOR MANIPULATION ----------------------------------------------
SELECT 'G1_monthly_targeting_status_mix' AS check_name,
    strftime('%Y-%m', target_date) AS month, status, COUNT(*) AS n
FROM raw_daily_targeting GROUP BY 1, 2 ORDER BY 1, 2;
-- Finding: CONTACTED / EXPIRED / QUEUED / SKIPPED each hold steady at ~25% of
-- the targeting population every month - no evidence that unsuccessful accounts
-- are being progressively dropped from the base used to compute rates.
