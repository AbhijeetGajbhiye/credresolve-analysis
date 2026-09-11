# Assignment Coverage Matrix

| Assignment requirement | Evidence in submission | Status |
|---|---|---|
| What happened / 12-month reconstruction | 8 observed calendar months: Jan-Jul complete + Aug partial; 12-month history is not present in supplied data and is explicitly flagged | COMPLETE WITH DATA LIMITATION |
| Why it happened / required drivers | DPD, loan type, risk, geography, campaign, channel, vendor, calling hour, attempt frequency, agent; unavailable client/language/tenure explicitly documented | COMPLETE WITH DATA LIMITATIONS |
| Challenge 11% recovery claim | Independent audited definition + targeted-yield comparison | COMPLETE |
| Contact / RPC / PTP / PTP kept | `operational_metrics_monthly.csv` + Metric Dictionary; contact implemented at attempt grain; PTP kept explicitly promised-date cohort | COMPLETE |
| Recovery rate / recovery per account | `operational_metrics_monthly.csv` | COMPLETE |
| Recovery per agent-hour | `operational_metrics_monthly.csv` | COMPLETE |
| Cost per ₹ recovered | Explicitly marked not calculable because no dependable cost table exists | COMPLETE WITH LIMITATION |
| Channel conversion | `channel_7d_conversion.csv`; mutually exclusive first targeting touch per account-month, next 7 full calendar days, target day excluded because target timestamp is unavailable | COMPLETE WITH DATE-GRAIN LIMITATION |
| Golden dataset | Golden/rejected payment layers + account-month spine | COMPLETE |
| Data forensics | Duplicate payments, attribution timing, timezone conflicts, vendor/disposition version stability, agent identity, mix, denominator | COMPLETE |
| Statistical investigation | Mix, common-cohort comparison, selection, survivorship, Simpson's paradox, attribution-window and time-series coverage; annual seasonality explicitly unavailable | COMPLETE WITH DATA LIMITATION |
| Counterfactual | Randomized holdout design, treatment/control, assumptions, confounders, identification, limitations | COMPLETE |
| ₹10 Cr recommendation | Targeting pilot; ~1.91 pp break-even hurdle based on targeted-payer economics; downside/base/stretch scenarios; experiment power plan aligned to payer-rate primary endpoint | COMPLETE |
| Production analytics | Raw→Staging→Clean→Golden→Feature→Metrics→Dashboard; data contracts, keys, lineage, incremental, late data, backfills, DQ and monitoring | COMPLETE |
| SQL repository | Reproducible SQLite pipeline + metric/statistical SQL | COMPLETE |
| Notebook | Executed reasoning notebook | COMPLETE |
| Dashboard | One-screen executive dashboard | COMPLETE |
| Executive memo | Two-page decision memo with uncertainty and financial framing | COMPLETE |
| Architecture diagram | Production design diagram | COMPLETE |

### Deliberate non-findings
Client, language, agent tenure and cost-per-recovery are not fabricated because the supplied data does not support reliable measurement. The assignment explicitly permits stating that additional data/experimentation is required when the data is insufficient.

### Evidence-window limitation
The raw extracts span 2026-01-01 through 2026-08-12, with January-July complete and August partial. The assignment requests approximately 12 months, but the supplied data does not provide that observation window. The submission therefore reports the observed period honestly rather than fabricating a 12-month series.
