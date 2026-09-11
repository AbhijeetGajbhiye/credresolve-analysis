# Data Contracts, Keys and Lineage

## Analytical grain and primary keys

| Source / layer | Grain | Primary key / uniqueness rule | Critical contract |
|---|---|---|---|
| borrowers | borrower snapshot row | borrower_id after identity-conflict flagging | Do not assume one immutable attribute history |
| accounts | account | account_id | Collection entity; borrower joins may be unavailable/orphaned |
| agents | agent master row | agent_id | Identity attributes are conflict-prone; descriptive use only |
| agent_sessions | agent session | session_id | login_at < logout_at; session hours are operational exposure, not payment attribution |
| campaigns | campaign definition | campaign_id | Treat windows/definitions as metadata, not automatic exclusion rules |
| daily_targeting | targeting touch | target_id | target_date is date-only; no target event time is supplied, so same-day pre/post ordering cannot be recovered |
| call_attempts | attempt event | attempt_id | Canonical attempt grain for contact rate; linked to canonical call_id when available |
| calls | call event | call_id after deterministic dedupe for KPI denominators | event_at + timezone required for calling-time metrics |
| call_dispositions | call disposition event | disposition_id; call_id links to call | Normalize disposition codes before RPC/PTP metrics |
| whatsapp_events / sms_events | digital event | event ID | Deduplicate event IDs/signatures before production reach metrics |
| promises_to_pay | promise event | ptp_id | PTP kept rate uses resolved KEPT/BROKEN statuses by promised-date cohort; resolution timestamp unavailable |
| payments | payment event | payment_id after deterministic dedupe | payment_reference ambiguity is a rejection rule for audited SUCCESS cash |
| vendor_telephony | vendor metadata | vendor_id | Vendor timezone mapping is used row-wise; mapping changes are monitored |
| account_status_history | account state event | status history event key | event_at is business time; recorded_at is latency/audit time |

## Layer lineage

`raw/*.csv` → **staging** schema normalization / parsing → **clean** duplicate + code / timezone controls → **golden** audited payment layer + account-month spine → **feature** DPD/risk/loan/target/channel/time features → **metrics** recovery + operations KPIs → **dashboard / memo**.

The canonical payment lineage is: raw payment rows → exact `payment_id` dedupe → payment-reference ambiguity classification → golden/rejected payment tables → all downstream recovery metrics.

## Incremental / late-arriving / backfill contract

- Process by event month using a stable event-time field; retain `recorded_at` for latency monitoring.
- Reprocess a rolling late-arrival window so late payments/calls can update the affected month without silently changing historical definitions.
- Backfills must rerun the canonical payment layer first, then metrics and dashboard extracts.
- DQ gates should fail the job on duplicate golden payment IDs, broken referential keys, schema drift, missing required timestamps, impossible session durations or unexplained metric discontinuities.

## Production monitoring

Track row counts, duplicate rates, orphan rates, payment rejection rates, timezone conflicts, disposition-code coverage, late-arrival volume, metric freshness, and recovery-cash anomalies. Alert thresholds should be versioned with the metric contract.
