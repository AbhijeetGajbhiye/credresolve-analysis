# SQL pipeline

SQLite-compatible SQL for staging, canonical payment auditing, monthly recovery metrics, data forensics, counterfactual design, driver analysis, and investment inputs.

## Important correction
`02_golden_payments.sql` now applies `payment_id` deduplication before calculating reused/ambiguous payment references. The exported `golden_payments.csv` and `rejected_payments.csv` are generated from the same canonical rule, eliminating the prior SQL/artifact seam.

`05_counterfactual.sql` and `07_targeting_investment.sql` no longer treat a full-month July payer flag as a causal outcome. Treatment is indexed at the first July targeting date, and the historical timing-aligned signal is treated as descriptive only. The production recommendation is a randomized holdout.


## Metric governance notes
`08_metric_governance.sql` uses `call_attempts` as the canonical contact-rate denominator, explicitly groups PTP kept/broken by promised-date cohort, and computes recovery/yield on targeted-account audited cash. `06_driver_analysis.sql` excludes the target date from the 7-day channel-conversion window because the target dataset has date-only timestamps.
