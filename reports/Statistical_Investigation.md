# Statistical Investigation

The supplied account table contains a current/extract-level DPD field rather than historical monthly DPD snapshots. The Jan-vs-Jul DPD decomposition therefore uses the available static DPD attribute and is explicitly descriptive, not a reconstructed historical DPD state. The assignment asks for explicit consideration of mix effects, cohort effects, selection bias, survivorship bias, Simpson's paradox, attribution-window bias, and time-series effects. The package now records each one explicitly.

## Mix effects — Strong evidence
The Jan→Jul targeted-yield movement is **+0.120 pp**. A common-cohort standardized comparison (using only age/DPD bands observed in both January and July) changes the result by **+0.121 pp**, showing that the headline movement is not explained by the disappearing 365+ cohort. DPD remains a static extract-level attribute because historical monthly snapshots are unavailable.

## Cohort effects — Investigated
Targeting performance is shown by account-age cohort for Jan and Jul in `reports/results/cohort_effects.csv`. The decision comparison also provides `cohort_effects_common.csv`, restricted to cohorts observed in **both** January and July, so the composition check is apples-to-apples. Cohort composition still moves materially, so cohort should remain a prespecified stratification/control variable.

## Selection bias — Quantified
July first-target treated vs untreated accounts are compared on DPD, outstanding amount, principal, risk segment, loan type, geography, first-target priority, prior 30-day call intensity/contact, prior month audited cash and prior payer behavior in `selection_balance_july.csv`. These are pre-treatment/anchor-safe features; selection is still not proven ignorable. Numeric standardized mean differences are small (DPD approximately -0.002; outstanding approximately +0.060; principal approximately -0.012), while the largest categorical share differences are under 0.01 for risk/loan-type categories. This reduces—but does not eliminate—selection concerns.

## Survivorship / denominator manipulation — Audited
`denominator_audit.csv` tracks the full 30,000-account master denominator alongside targeted accounts and audited payers by month. The all-account recovery metric uses audited payments rather than only successful/targeted accounts, while targeted yield explicitly uses targeted principal. There is no evidence that unsuccessful accounts are silently removed from the all-account denominator.

## Simpson's paradox — Investigated
No complete sign reversal by DPD bucket; within-band changes are mixed, while aggregate yield rises. The quantified DPD mix contribution is only +0.00005 pp.

## Attribution-window bias — Corrected
The legacy July full-month targeting association can include payments before first targeting. It is retained as a diagnostic only. The corrected historical view uses seven **full calendar days before** and seven **full calendar days after**, excluding the entire target day because the source has no target timestamp. It remains descriptive, not causal.

## Time-series effects — Investigated
The available monthly series covers 8 observed calendar months (Jan-Jul complete; Aug partial). It is retained as the observed trend view, but annual seasonality cannot be assessed from less than 12 months. The corrected target signal is not interpreted as causal because pre/post comparisons remain exposed to seasonality, regression to the mean, collection-cycle effects and concurrent interventions.

## Counterfactual — Decision grade
The production answer is a randomized 5–10% holdout stratified by DPD × risk × loan type, with treatment assigned before the outcome window. Primary statistical endpoint: 30-day payer rate. Financial decision metric: 30-day audited cash per eligible account. Guardrails are tested separately so the power calculation matches the primary hypothesis endpoint. Guardrails: PTP kept, complaints, contact rate and spillover.

## Experiment sizing
Using a planning baseline of approximately 1.29% payer rate and the corrected targeted-population break-even target of +1.91 percentage points, a normal-approximation two-proportion calculation indicates roughly **347 control + 3,117 treatment accounts (~3,464 total)** for 80% power at two-sided 5% alpha under 90/10 allocation. The 5% holdout variant requires ~6,150 total accounts. A 10% holdout therefore provides the planned minimum control size within a 5,666-account July cohort, subject to recalculation against the actual 30-day baseline and final endpoint variance assumptions. This is a planning calculation, not a substitute for final power analysis against the actual 30-day endpoint.


## Confidence around the corrected descriptive signal
A paired bootstrap on the 5,666 July first-target accounts gives a descriptive 95% interval of approximately **-0.371 pp to +0.459 pp** around the **+0.035 pp** payer-rate movement. This interval is not causal because treatment was not randomized. The investment section therefore uses scenario/rule-based financial ranges and a prospective randomized test rather than a historical causal confidence interval.

## Vendor/disposition forensics — Strong evidence
Disposition versions (legacy/v1/v2) are present throughout the observed period; the largest month-level version-share spread is only about 2.5 percentage points. The normalized RPC-code share is also stable across versions (about 66.0%-66.4%). A raw-code/version mapping and before/after table is provided in `vendor_disposition_code_mapping.csv` and `vendor_disposition_before_after.csv`. **No distributional break is evident after version-normalized grouping, but semantic equivalence across versions cannot be conclusively established without an authoritative vendor disposition dictionary.**
