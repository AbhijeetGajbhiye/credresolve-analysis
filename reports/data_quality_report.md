# Data Quality Report — CredResolve Collections Analytics

## 1. Overview

17 raw tables, ~640K total rows, covering Jan 1 – Aug 8, 2026 (partial). This
report documents every data-quality issue found, how it was detected, how it
was treated, and its quantified business impact. Full detection queries are in
`sql/04_forensics.sql`; the cleaning pipeline is in `pipeline/build_golden_dataset.py`
(Python) and `sql/01_staging.sql` + `sql/02_golden_dataset.sql` (SQL) — the two
were built independently and cross-checked against each other for the headline
metrics (they agree to within rounding).

## 2. Major issues, by forensics category (Part 2, A–G)

### A. Duplicate payments — CONFIRMED, quantified
- 486 exact full-row duplicate rows + 14 duplicate `payment_id` collisions =
  **500 of 25,500 raw payment rows (1.96%)** are ingestion duplicates.
- Impact: raw SUCCESS-status recovered amount is overstated by ~2% before cleaning.
- Checked separately for "same account + same amount within 60 minutes but
  different payment_id" (a retry-with-new-id signature): after removing the
  exact/ID duplicates above, this check returns **zero** additional cases — the
  duplicate-payment problem in this dataset IS the exact/ID-duplicate issue, not
  a separate retry pattern requiring fuzzy matching.
- Treatment: dropped in golden layer, kept first-seen occurrence.

### B. Attribution errors — CONFIRMED, but different from the hypothesis
- The `payments` table has **no campaign_id or interaction_id column at all** —
  any "which channel drove this recovery" attribution must be derived by
  joining to interaction timestamps. This absence is itself a data-quality
  finding: today's channel-conversion reporting, whatever method it uses, is an
  analytical construct layered on top of the raw feed, not a measured fact.
- We tested the specific hypothesis in the brief (last-touch over-crediting a
  high-frequency automated channel): on a 3,000-payment sample, last-touch and
  split multi-touch credit agree within ~1 percentage point per channel.
  **No material last-touch bias found.**
- A bigger issue: only **36% of successful payments have any recorded
  interaction (call/WhatsApp/SMS/field visit) within 14 days beforehand.**
  Channel-conversion and channel-ROI metrics for the other 64% rest on no
  observed link at all and should be treated as low-confidence.

### C. Timezone problems — CONFIRMED
- `calls`, `accounts`, and `agent_sessions` each carry a `timezone` field with
  three values: UTC, Asia/Kolkata, Asia/Dubai, and timestamps are stored
  naive-local (not normalized) in the raw feed.
- Treatment: golden layer converts every timestamp to a canonical UTC value
  using a fixed offset per zone (+5:30 for Kolkata, +4:00 for Dubai — both
  exact, since neither India nor the UAE observes daylight saving), while
  retaining local time for calling-time-of-day analysis.
- Impact check: with normalization applied, connect rate by hour-of-day is flat
  (18.1–20.9% in every hour) — timezone misclassification does not appear to be
  masking a real daypart effect in this dataset, but it would have been
  impossible to rule that out without the fix.

### D. Vendor/disposition code changes — CONFIRMED, different shape than expected
- `call_dispositions.disposition_code` contains both `PTP` and `PROMISE_TO_PAY`
  as separate strings for the same outcome — **3,926 rows**, split roughly
  evenly across all three `disposition_version` values (legacy/v1/v2). This is
  a labeling inconsistency independent of the version field, not a clean
  legacy-vs-new cutover.
- Treatment: canonicalized to `PTP` in the golden layer; raw value retained as
  `disposition_code_raw` for audit.

### E. Agent identity problems — CONFIRMED, severe
- 1,000 real agents (by `agent_id`, the key every fact table references) are
  represented by 30,000 raw dimension rows — **14 to 48 snapshot rows per
  agent**, with `employee_code`, `vendor_id`, `team`, and `name` reshuffled
  essentially at random between snapshots for the same `agent_id`.
- **100% of agent_ids** (1,000/1,000) show more than one `employee_code` across
  their raw rows. `employee_code` is not usable as an identity or dedup key in
  this feed.
- Treatment: `agent_id` adopted as the sole entity key; dimension collapsed to
  one row per `agent_id` via latest-`updated_at` (standard SCD-1), with an
  explicit flag that pre-collapse attribute history should not be read as real
  employee movement.
- The same pattern exists in `borrowers` (11,015 real borrowers behind 30,600
  raw rows, 1–11 inconsistent snapshots each) and was treated the same way.

### F. Portfolio mix changes — TESTED, NOT FOUND
- Monthly composition of targeted accounts by `risk_segment`, `dpd_bucket`, and
  `loan_type` is flat within 1–2 percentage points every month (see
  `golden_dataset/golden_driver_*.csv`). **No evidence of a portfolio
  acquisition or mix shift** during the observed window.

### G. Denominator manipulation — TESTED, NOT FOUND
- Monthly mix of `daily_targeting.status` (CONTACTED / EXPIRED / QUEUED /
  SKIPPED) holds at roughly 25% each, every month. **No evidence that
  unsuccessful accounts are being progressively excluded** from the population
  used to compute rates.
- A different, unrelated denominator issue **was** found and is the single
  most actionable finding in this report — see next section.

## 3. The coverage gap (new finding, not in the original A–G checklist)

**6,656 of 30,000 accounts (22.2%, ₹231.1 crore of outstanding balance) never
appear in `daily_targeting` at all**, in the entire observed window. These
accounts are statistically indistinguishable from the worked book on account
status mix, risk segment mix, average DPD (56.3 vs 56.6 days), and average
outstanding balance (₹347K vs ₹350K). This is not a data-quality *error* so
much as an operational blind spot the data quality investigation surfaced —
see the Executive Memo for the resulting investment recommendation.

## 4. Issues investigated and explicitly ruled out

| Hypothesis | Result |
|---|---|
| Portfolio mix shift explains the "11% improvement" | Ruled out — mix is flat (Section F) |
| Denominator shrinkage inflates conversion rates over time | Ruled out — targeting status mix is flat (Section G) |
| Last-touch attribution over-credits automated channels | Ruled out — last-touch ≈ multi-touch credit (Section B) |
| Calling-hour or attempt-number effects are hidden by timezone noise | Ruled out — flat even after UTC normalization |
| Agent tenure affects connect rate | Ruled out — the only two populated tenure bands are statistically identical |

## 5. What the 11% actually is

See `notebook/analysis.ipynb` Section 4 for the full derivation. In short:
raw SUCCESS-status recovery amount rose from ₹174.1M (February, 28 days) to
₹193.2M (March, 31 days) — a **+10.99%** raw month-over-month change that
matches the reported figure almost exactly. Normalized to recovery-per-day,
the same comparison shows **+0.29%**. Every month in the window shows the same
pattern: raw totals swing ±5–11% purely from day-count differences, while
per-day figures stay in a ₹5.8–6.1M/day band with no trend.

**Recommendation for reporting going forward:** never compare raw monthly
totals month-over-month in this business without day-count normalization, and
prefer a 3-month rolling average of the per-day metric for the headline
leadership number, since single-month comparisons are dominated by calendar
noise larger than the real signal being measured.
