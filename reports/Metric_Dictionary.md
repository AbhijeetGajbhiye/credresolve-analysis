# Metric Dictionary and Definition Governance

| Metric | Production definition | Denominator | Data status | Why this definition |
|---|---|---|---|---|
| Contact rate | Distinct deduped **call attempts linked to an ANSWERED canonical call** / distinct deduped call attempts | Call attempts | Calculable | Uses the attempt grain for both numerator and denominator; avoids mixing call-level and attempt-level units |
| RPC | Distinct calls with a normalized right-party disposition / answered calls | Answered calls | Calculable | Disposition mapping captures contact beyond mere technical answer |
| PTP rate | Distinct calls with PTP/PROMISE_TO_PAY disposition / RPC calls | RPC calls | Calculable | Measures commitment conversion after right-party contact |
| PTP kept rate | Resolved KEPT promises / (resolved KEPT + resolved BROKEN promises), grouped by promised-date cohort | Resolved promises in the promised-date cohort | Calculable | Status-resolution timestamp is unavailable; the cohort is explicitly promised-date based and excludes OPEN/CANCELLED |
| Recovery rate / yield | Audited SUCCESS cash on targeted accounts / targeted principal | Targeted principal | Calculable | The audited denominator is explicit and reproducible; full portfolio outstanding is not a stable snapshot |
| Recovery per account | Audited SUCCESS cash / distinct targeted accounts | Targeted accounts | Calculable | Decision-safe unit economics without inventing causality |
| Recovery per agent-hour | All-account audited SUCCESS cash / total logged agent-session hours | Agent session hours | Calculable, attribution-free | This is a **portfolio cash per human-session-hour proxy**, not attributable agent productivity; the numerator includes digital, field and borrower-initiated recoveries |
| Cost per ₹ recovered | Total collection cost / audited recovery cash | Audited recovery cash | **Not calculable** | No dependable cost table was supplied; do not fabricate |
| Channel conversion | Audited payer in the **next 7 full calendar days after the first targeting touch for an account-month** / unique first targeting touches; target date excluded because no target timestamp exists | Unique first targeting touches | Calculable with date-grain limitation | Mutually exclusive first-touch attribution avoids double-counting one payment across multiple channel windows; target day is excluded because treatment time is unavailable |

## Unavailable requested dimensions

- **Client:** no client/lender field exists in supplied schemas.
- **Language:** no language field exists.
- **Agent tenure:** `agent_id` history conflicts across the full agent universe, so tenure is not reliable enough for causal inference.
- **Dedicated borrower segment:** no standalone borrower-segment field exists; `risk_segment` is used only as the closest available account-level stratification and is explicitly not renamed as borrower segment.

Cost-per-recovery is therefore not reported as a numeric KPI. The investment section uses a budget hurdle instead.


**Implementation control:** the production KPI layer now computes targeted recovery cash by joining canonical audited payments to the same-month targeted account set before calculating recovery rate and recovery/account. All-account audited cash remains separately reported for executive portfolio recovery.

## Temporal data caveats

- `daily_targeting.target_date` is date-only. The historical first-target signal therefore excludes the **entire target day** and compares seven full calendar days before vs seven full calendar days after the target date.
- `golden_account_month.csv.gz` labels `*_extract` fields as current/extract-level attributes. They are not monthly historical snapshots.
