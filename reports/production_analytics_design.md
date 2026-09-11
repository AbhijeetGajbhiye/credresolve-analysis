# Production Analytics Design — CredResolve Collections

## 1. Pipeline architecture

```
Raw  →  Staging  →  Clean  →  Golden  →  Feature  →  Metrics  →  Dashboard
```

See `architecture/architecture_diagram.svg` for the full system diagram
(orchestration, monitoring, and consumer layers included).

| Layer | Purpose | This assignment's equivalent |
|---|---|---|
| **Raw** | Immutable landing zone, one folder/table per source system, partitioned by ingestion date. No transformation. | `raw/*.csv` |
| **Staging** | Exact-duplicate removal, natural-key dedup, type casting. No business logic. | `sql/01_staging.sql` |
| **Clean** | Entity resolution (agents, borrowers), timezone normalization, code canonicalization (PTP/PROMISE_TO_PAY). | `pipeline/build_golden_dataset.py`, `sql/02_golden_dataset.sql` |
| **Golden** | One trustworthy table per entity/fact, documented source-of-truth decisions. | `golden_dataset/*.csv` |
| **Feature** | Derived attributes: dpd_bucket, session_hours, tenure_bucket, last-touch channel. | Views in `sql/05_driver_analysis.sql` |
| **Metrics** | Redefined, versioned metric definitions (contact rate, RPC, PTP rate, etc.), computed daily. | `sql/03_metrics.sql` |
| **Dashboard** | One-screen leadership view, refreshed daily. | `dashboard/dashboard.html` |

## 2. Data contracts

Each source system owns a contract specifying: schema (with a version number),
required fields, key uniqueness guarantee, freshness SLA, and a change-notification
process. Concretely for this system:

- **Telephony/dialer feed** (calls, call_attempts, call_dispositions): contract
  requires `call_id`/`attempt_id`/`disposition_id` to be globally unique once
  assigned, `event_at` + `timezone` both populated, and 30 days' notice before any
  disposition code taxonomy change (this dataset shows that notice was not honored
  historically — `PTP`/`PROMISE_TO_PAY` coexisted for the entire observed window).
- **Core banking / LMS feed** (accounts, borrowers): contract requires
  `account_id`/`borrower_id` stability for the life of the loan, and an explicit
  `updated_at` on every row (present, but not sufficient on its own — see below).
- **Payments/collections platform** (payments): contract requires a payment
  gateway-issued idempotency key on every row. This dataset's `payment_reference`
  is not a reliable idempotency key (duplicate references appear on unrelated
  failed transactions) — this should be a hard requirement, not optional, going
  forward.

## 3. Primary keys and grain

| Table | Grain | Primary key | Notes |
|---|---|---|---|
| accounts | 1 row per loan account | account_id | Stable, no issues found |
| borrowers | 1 row per borrower **as of latest update** | borrower_id | Raw feed is SCD (multiple snapshots); golden layer is latest-only. **Recommendation: the raw feed should be ingested as an explicit SCD Type 2 table (with valid_from/valid_to) rather than unlabeled repeated rows, so "latest" is a query-time choice, not a load-time destructive decision.** |
| agents | 1 row per agent **as of latest update** | agent_id | Same SCD recommendation as borrowers. `employee_code` should not be used as a key anywhere downstream. |
| calls / call_attempts / call_dispositions / whatsapp_events / sms_events / field_visits / promises_to_pay / payments / complaints / account_status_history | 1 row per event | `{table}_id` | All require exact-duplicate and id-collision dedup at staging |
| daily_targeting | 1 row per account per targeting decision | target_id | — |

## 4. Metric definitions (versioned)

Every metric in `sql/03_metrics.sql` should be registered in a metrics catalog
with: name, formula, owner, effective date, and superseded-by pointer if
redefined. This assignment redefines 5 of the business's existing metrics
(contact rate, RPC rate, PTP rate, PTP kept rate, recovery per account) — in
production, the OLD definitions should not be silently replaced; both should
run in parallel for at least one full reporting cycle so leadership can see the
reconciliation, exactly as this report does in `metric_naive_vs_normalized`.

## 5. Data lineage

Every golden table carries `_source_table`, `_pipeline_run_id`, and
`_cleaning_rule_version` columns (added at the Clean stage) so any number in
the dashboard can be traced back to the exact raw rows and cleaning decision
that produced it. This is what `golden_dataset/_data_quality_log.csv` does
manually for this assignment; in production it should be a first-class column
on every table, not a side log.

## 6. Incremental processing & late-arriving data

- Staging and Clean layers run as daily incremental jobs keyed on
  `event_at`/`updated_at` watermarks, not full reprocessing.
- **Late-arriving events**: this dataset's cross-timezone timestamps mean a
  midnight-adjacent event can arrive after its logical day has already been
  processed. Recommendation: hold each day's Golden partition open for 48
  hours before treating it as final, and support upsert-by-id rather than
  append-only, so a late-arriving call_disposition can still attach to the
  correct call.
- **Backfills**: any change to a cleaning rule (e.g., a new PTP code synonym
  discovered next quarter) must re-run from Staging forward for the affected
  date range, not patch the Golden table directly — otherwise lineage breaks.

## 7. Data-quality checks & monitoring

Run automatically after every Staging→Clean load, before Clean→Golden promotion:

1. **Volume check**: row count per table within ±20% of trailing-7-day average (would have caught nothing unusual here, but is the cheapest possible early warning).
2. **Key uniqueness check**: 0 duplicate `{table}_id` post-dedup (this assignment found up to 100% duplication rate in `agents` pre-dedup — this check must run on RAW as well as GOLDEN, so the size of the problem is visible, not just its absence after cleaning).
3. **Referential integrity**: every `account_id`/`agent_id`/`borrower_id` in a fact table exists in its dimension table.
4. **Distribution drift check**: monthly categorical mix (risk_segment, dpd_bucket, channel) compared to trailing 3-month average via a simple population stability index — this is what would have caught a REAL portfolio mix shift, had one existed.
5. **Metric sanity bounds**: contact rate, RPC rate, PTP rate, PTP-kept rate each within a hard-coded plausible range (e.g., 0–100%, obviously, but also business-informed bounds like contact rate not exceeding ~40% for outbound cold-dial collections) — alert, don't block, on breach.
6. **Calendar-normalization check**: any headline metric reported as a raw period total must have a paired day-normalized version computed and displayed alongside it — a direct, permanent fix for the exact reporting failure this assignment investigates.

## 8. Anomaly detection

A lightweight approach is preferred over an unexplainable model, per the
assignment's own guidance:

- Each of the ~10 metrics in the catalog gets a rolling 8-week mean and
  standard deviation; a daily value more than 2.5 standard deviations away
  triggers a Slack/email alert to the analytics on-call, with the specific
  contributing dimension (segment/channel/vendor) auto-attached via the same
  driver breakdown queries used in `sql/05_driver_analysis.sql`.
- This is intentionally simple (a z-score, not an ML anomaly detector) because
  the actual root cause found in this assignment — a calendar-day artifact —
  would have been caught by simple day-normalization, not by a more
  sophisticated model. Complexity should be added only where a documented
  incident shows the simple check missed something.
