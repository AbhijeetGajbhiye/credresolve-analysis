-- ============================================================================
-- 02_golden_dataset.sql
-- Golden layer: one trustworthy table per entity/fact, business-ready.
-- Run after 01_staging.sql.
-- ============================================================================

DROP TABLE IF EXISTS golden_borrowers;
CREATE TABLE golden_borrowers AS SELECT * FROM stg_borrowers;

DROP TABLE IF EXISTS golden_agents;
CREATE TABLE golden_agents AS SELECT * FROM stg_agents;

DROP TABLE IF EXISTS golden_accounts;
CREATE TABLE golden_accounts AS
SELECT *,
    CASE
        WHEN dpd = 0 THEN '0'
        WHEN dpd BETWEEN 1 AND 30 THEN '1-30'
        WHEN dpd BETWEEN 31 AND 60 THEN '31-60'
        WHEN dpd BETWEEN 61 AND 90 THEN '61-90'
        ELSE '90+'
    END AS dpd_bucket
FROM stg_accounts;

DROP TABLE IF EXISTS golden_calls;
CREATE TABLE golden_calls AS
SELECT *,
    event_at AS event_at_local,
    -- SQLite has no IANA tz database; India and UAE do not observe DST, so a
    -- fixed UTC offset per stated zone is exact (not an approximation).
    CASE timezone
        WHEN 'Asia/Kolkata' THEN datetime(event_at, '-5 hours', '-30 minutes')
        WHEN 'Asia/Dubai'   THEN datetime(event_at, '-4 hours')
        ELSE event_at  -- already UTC
    END AS event_at_utc
FROM stg_calls
WHERE direction = 'OUTBOUND';

DROP TABLE IF EXISTS golden_call_attempts;
CREATE TABLE golden_call_attempts AS SELECT * FROM stg_call_attempts;

DROP TABLE IF EXISTS golden_call_dispositions;
CREATE TABLE golden_call_dispositions AS SELECT * FROM stg_call_dispositions;

DROP TABLE IF EXISTS golden_whatsapp_events;
CREATE TABLE golden_whatsapp_events AS SELECT * FROM stg_whatsapp_events;

DROP TABLE IF EXISTS golden_sms_events;
CREATE TABLE golden_sms_events AS SELECT * FROM stg_sms_events;

DROP TABLE IF EXISTS golden_field_visits;
CREATE TABLE golden_field_visits AS SELECT * FROM stg_field_visits;

DROP TABLE IF EXISTS golden_promises_to_pay;
CREATE TABLE golden_promises_to_pay AS SELECT * FROM stg_promises_to_pay;

DROP TABLE IF EXISTS golden_complaints;
CREATE TABLE golden_complaints AS SELECT * FROM stg_complaints;

DROP TABLE IF EXISTS golden_account_status_history;
CREATE TABLE golden_account_status_history AS SELECT * FROM stg_account_status_history;

DROP TABLE IF EXISTS golden_payments;
CREATE TABLE golden_payments AS
SELECT *,
    CASE WHEN payment_status = 'SUCCESS' THEN 1 ELSE 0 END AS is_success
FROM stg_payments;

DROP TABLE IF EXISTS golden_campaigns;
CREATE TABLE golden_campaigns AS SELECT * FROM stg_campaigns;

DROP TABLE IF EXISTS golden_daily_targeting;
CREATE TABLE golden_daily_targeting AS SELECT * FROM stg_daily_targeting;

DROP TABLE IF EXISTS golden_vendor_telephony;
CREATE TABLE golden_vendor_telephony AS SELECT * FROM stg_vendor_telephony;

DROP TABLE IF EXISTS golden_agent_sessions;
CREATE TABLE golden_agent_sessions AS
SELECT *,
    (JULIANDAY(logout_at) - JULIANDAY(login_at)) * 24.0 AS session_hours
FROM raw_agent_sessions;
