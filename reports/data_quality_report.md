# Data Quality Report

| Issue | Detection | Treatment | Business impact |
|---|---|---|---|
| Duplicate payments | 500 duplicate `payment_id` rows | Exact dedupe first; then calculate reference ambiguity | Prevents payment-count inflation and creates a single canonical payment layer |
| Ambiguous payment references | 3,406 reused/ambiguous references after payment-id dedupe | Exclude ambiguous references from audited recovery; retain in rejected layer | Raw SUCCESS cash ₹134.15 Cr -> audited ₹93.53 Cr |
| Duplicate calls | 1,350 duplicate `call_id` rows | Remove exact duplicate signatures; retain conflicting IDs with flags | Prevents inflated calling metrics |
| Duplicate WhatsApp events | 600 duplicate event IDs | Deduplicate by event ID/signature | Prevents inflated digital reach |
| Borrower identity drift | 30,600 borrower rows collapse to 11,015 borrower IDs; 8,518 IDs have conflicting attributes | Use `account_id` as collection entity; borrower joins optional | Prevents borrower-level misattribution |
| Account referential integrity | 455 accounts missing borrower ID; 2,913 orphan accounts | Keep accounts; mark demographic joins unavailable | Avoids denominator loss |
| Agent identity drift | 30,000 agent rows collapse to 1,000 agent IDs | Do not use agent tenure/identity for causal conclusions | Limits agent-level inference |
| Status timestamps | 30,191 rows have `recorded_at < event_at` | Use `event_at` for business timing; retain `recorded_at` for latency monitoring | Reduces period/hour misclassification |
| Timezone conflicts | 60,961/91,350 calls differ from vendor timezone | Use row-level timezone consistently | Keeps calling-hour analysis internally consistent |
| Campaign window mismatch | Events/targets exist outside campaign windows | Do not hard-exclude activity on campaign-window logic | Avoids deleting real collection activity |
| Cost data | No dependable cost table | Do not invent cost metrics; use budget hurdle analysis | Limits ROI precision |

## Raw -> corrected -> golden

The payment pipeline now applies one deterministic order: **raw payment rows -> exact `payment_id` dedupe -> reference ambiguity classification -> golden/rejected payment layers**. The exported CSV artifacts are generated from that same sequence.

## Targeting correction

The earlier full-month July payer comparison could count a payment that occurred before the first targeting event. That construction is retained only as a legacy diagnostic and is explicitly excluded from investment decisioning.

The corrected historical signal indexes each July-targeted account at its first target date and uses seven full calendar days before versus seven full calendar days after the target date, **excluding the entire target day** because the source has no target timestamp. In the corrected data, the 7-day payer rate moves by **+0.035 percentage points**. A paired bootstrap gives a 95% descriptive interval of approximately **-0.371 pp to +0.459 pp**. Average audited cash per targeted account is lower post-target; this is descriptive and not causal.

These are observational and can still reflect time trends, regression to the mean, borrower selection, or other confounding. The production design therefore uses a randomized 5-10% holdout.

## Investment hurdle

The annualized addressable population is 67,104 target account-month opportunities. Using July audited recovery per payer **among targeted July accounts**, a ₹10 Cr annual return requires approximately **1.91 percentage points of incremental payer lift**. Historical observational data does not establish that hurdle.

## Statistical investigation coverage
See `reports/Statistical_Investigation.md` for explicit treatment of mix, cohort, selection, survivorship/denominator manipulation, Simpson's paradox, attribution-window bias and time-series effects.

## Requested metric governance
See `reports/Metric_Dictionary.md`. Contact rate is calculated at the call-attempt grain; RPC/PTP use normalized disposition definitions; PTP kept is a promised-date cohort metric; recovery/yield uses targeted-account cash; and channel conversion uses the next 7 full calendar days after a target date with the target date excluded because target timestamps are unavailable. Cost per ₹ recovered is deliberately not calculated because no dependable cost table was supplied.

## Statistical investigation coverage
See `reports/Statistical_Investigation.md` for explicit treatment of mix, cohort, selection, survivorship/denominator manipulation, Simpson's paradox, attribution-window bias and time-series effects.

## Requested metric governance
See `reports/Metric_Dictionary.md`. Contact rate is calculated at the call-attempt grain; RPC/PTP use normalized disposition definitions; PTP kept is a promised-date cohort metric; recovery/yield uses targeted-account cash; and channel conversion uses the next 7 full calendar days after a target date with the target date excluded because target timestamps are unavailable. Cost per ₹ recovered is deliberately not calculated because no dependable cost table was supplied.

## Observation-window limitation
The supplied extracts cover 2026-01-01 through 2026-08-12: seven complete months (Jan-Jul) plus partial August. The assignment asks for approximately 12 months, but the supplied data does not contain a full 12-month history. No annual seasonality conclusion is therefore made.
