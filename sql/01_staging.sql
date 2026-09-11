-- ============================================================================
-- 01_staging.sql
-- Staging layer: exact-duplicate and natural-key deduplication only.
-- No business logic here, just "one row per raw event/record" hygiene.
-- ============================================================================

DROP VIEW IF EXISTS stg_borrowers;
CREATE VIEW stg_borrowers AS
SELECT *
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY borrower_id ORDER BY updated_at DESC) AS rn
    FROM raw_borrowers
) t
WHERE rn = 1;
-- Note: latest-updated_at wins per borrower_id. See DQ report: attributes are
-- inconsistent across snapshots in this feed; latest-wins is a documented policy
-- decision, not a claim that the latest row is factually more accurate.

DROP VIEW IF EXISTS stg_agents;
CREATE VIEW stg_agents AS
SELECT *
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY agent_id ORDER BY updated_at DESC) AS rn
    FROM raw_agents
) t
WHERE rn = 1;
-- agent_id is the stable FK used by every fact table; employee_code/team/vendor
-- are NOT stable across snapshots for the same agent_id in this feed.

DROP VIEW IF EXISTS stg_accounts;
CREATE VIEW stg_accounts AS
SELECT DISTINCT * FROM raw_accounts;

DROP VIEW IF EXISTS stg_calls;
CREATE VIEW stg_calls AS
SELECT *
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_calls)
) t
WHERE rn = 1;

DROP VIEW IF EXISTS stg_call_attempts;
CREATE VIEW stg_call_attempts AS
SELECT *
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY attempt_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_call_attempts)
) t
WHERE rn = 1;

DROP VIEW IF EXISTS stg_call_dispositions;
CREATE VIEW stg_call_dispositions AS
SELECT
    disposition_id, account_id, borrower_id, event_at, call_id, agent_id,
    CASE WHEN disposition_code = 'PROMISE_TO_PAY' THEN 'PTP' ELSE disposition_code END AS disposition_code,
    disposition_code AS disposition_code_raw,
    disposition_version
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY disposition_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_call_dispositions)
) t
WHERE rn = 1;
-- 'PROMISE_TO_PAY' and 'PTP' are the same outcome under two code strings; canonicalized here.

DROP VIEW IF EXISTS stg_whatsapp_events;
CREATE VIEW stg_whatsapp_events AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY whatsapp_event_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_whatsapp_events)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_sms_events;
CREATE VIEW stg_sms_events AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY sms_event_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_sms_events)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_field_visits;
CREATE VIEW stg_field_visits AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY visit_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_field_visits)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_promises_to_pay;
CREATE VIEW stg_promises_to_pay AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY ptp_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_promises_to_pay)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_complaints;
CREATE VIEW stg_complaints AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY complaint_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_complaints)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_account_status_history;
CREATE VIEW stg_account_status_history AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY history_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_account_status_history)
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_payments;
CREATE VIEW stg_payments AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at) AS rn
    FROM (SELECT DISTINCT * FROM raw_payments)
) t WHERE rn = 1;
-- Removes exact-duplicate rows (ingestion replays) and duplicate payment_id
-- collisions (486 + 14 rows respectively on the 2026 dataset). See
-- 04_forensics.sql for the near-duplicate (same account+amount+<1hr, different
-- payment_id) sensitivity check, which is flagged but NOT auto-removed here.

DROP VIEW IF EXISTS stg_campaigns;
CREATE VIEW stg_campaigns AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY end_at DESC) AS rn
    FROM raw_campaigns
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_daily_targeting;
CREATE VIEW stg_daily_targeting AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY target_id ORDER BY target_date DESC) AS rn
    FROM raw_daily_targeting
) t WHERE rn = 1;

DROP VIEW IF EXISTS stg_vendor_telephony;
CREATE VIEW stg_vendor_telephony AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY vendor_id ORDER BY vendor_id) AS rn
    FROM raw_vendor_telephony
) t WHERE rn = 1;
