"""
CredResolve Collections Analytics - Golden Dataset Pipeline
=============================================================
Raw -> Rejected/Corrected -> Golden

Run: python3 build_golden_dataset.py
Reads from ../raw/*.csv, writes to ../golden_dataset/*.csv
Writes a data-quality log (json + csv) documenting every decision made
and its quantified impact, for the Data Quality Report.
"""
import pandas as pd
import numpy as np
import json
import os

RAW = "../raw"
OUT = "../golden_dataset"
os.makedirs(OUT, exist_ok=True)

log = []  # one entry per cleaning decision, for the DQ report

def record(table, step, raw_n, kept_n, note):
    log.append(dict(table=table, step=step, raw_rows=raw_n, kept_rows=kept_n,
                     removed_rows=raw_n - kept_n, note=note))

TZ_MAP = {"UTC": "UTC", "Asia/Kolkata": "Asia/Kolkata", "Asia/Dubai": "Asia/Dubai"}

def to_utc(df, ts_col, tz_col):
    """Treat event_at as naive-local time in the stated timezone; return true UTC timestamp."""
    out = pd.Series(pd.NaT, index=df.index, dtype="datetime64[ns, UTC]")
    for tz_name in df[tz_col].dropna().unique():
        mask = df[tz_col] == tz_name
        local = pd.to_datetime(df.loc[mask, ts_col])
        out.loc[mask] = local.dt.tz_localize(tz_name, ambiguous="NaT", nonexistent="NaT").dt.tz_convert("UTC")
    return out

# ---------------------------------------------------------------
# 1. BORROWERS  (SCD-style snapshots, noisy attributes -> latest wins)
# ---------------------------------------------------------------
b = pd.read_csv(f"{RAW}/borrowers.csv")
raw_n = len(b)
b["updated_at"] = pd.to_datetime(b["updated_at"])
b_golden = (b.sort_values("updated_at")
              .drop_duplicates(subset=["borrower_id"], keep="last")
              .reset_index(drop=True))
record("borrowers", "collapse_to_latest_snapshot_per_borrower_id", raw_n, len(b_golden),
       "Raw feed carries 1-11 snapshot rows per borrower_id with mutually inconsistent "
       "name/phone/email/city/state. No reliable resolution exists in a synthetic feed "
       "with random per-row attributes, so we apply standard SCD-1 latest-wins by updated_at "
       "and flag borrower demographic fields as low-trust for this dataset.")
b_golden.to_csv(f"{OUT}/golden_borrowers.csv", index=False)

# ---------------------------------------------------------------
# 2. AGENTS  (same pattern, keyed on agent_id which IS the stable FK used everywhere else)
# ---------------------------------------------------------------
a = pd.read_csv(f"{RAW}/agents.csv")
raw_n = len(a)
a["updated_at"] = pd.to_datetime(a["updated_at"])
a_golden = (a.sort_values("updated_at")
              .drop_duplicates(subset=["agent_id"], keep="last")
              .reset_index(drop=True))
record("agents", "collapse_to_latest_snapshot_per_agent_id", raw_n, len(a_golden),
       "1,000 real agent_ids carry 14-48 raw rows each with randomly reshuffled "
       "employee_code/vendor_id/team/name. agent_id is the only stable key (it is what "
       "calls/attempts/dispositions/PTPs/field_visits actually reference), so it is treated "
       "as the entity key. employee_code is NOT usable as an identity or dedup key in this feed.")
a_golden.to_csv(f"{OUT}/golden_agents.csv", index=False)

# ---------------------------------------------------------------
# 3. ACCOUNTS  (clean key, no exact dupes, keep as-is but standardize dtypes)
# ---------------------------------------------------------------
acc = pd.read_csv(f"{RAW}/accounts.csv")
raw_n = len(acc)
acc["opened_at"] = pd.to_datetime(acc["opened_at"])
acc_golden = acc.drop_duplicates(subset=["account_id"], keep="last").reset_index(drop=True)
record("accounts", "dedupe_by_account_id", raw_n, len(acc_golden), "No exact duplicates found; account_id is a clean 1:1 key.")
acc_golden.to_csv(f"{OUT}/golden_accounts.csv", index=False)

# ---------------------------------------------------------------
# 4. CALLS  (exact dup rows + duplicate call_id + timezone normalization)
# ---------------------------------------------------------------
calls = pd.read_csv(f"{RAW}/calls.csv")
raw_n = len(calls)
calls = calls.drop_duplicates()
after_exact = len(calls)
calls = calls.drop_duplicates(subset=["call_id"], keep="first")
after_id = len(calls)
calls["event_at_utc"] = to_utc(calls, "event_at", "timezone")
calls["event_at_local"] = pd.to_datetime(calls["event_at"])
record("calls", "drop_exact_duplicate_rows", raw_n, after_exact, "Ingestion produced full-row duplicates (retries/replays).")
record("calls", "dedupe_by_call_id_keep_first", after_exact, after_id, "Remaining call_id collisions kept as first-seen occurrence.")
record("calls", "normalize_timestamp_to_utc", after_id, after_id,
       "event_at is naive-local in the stated timezone (UTC / Asia/Kolkata / Asia/Dubai). "
       "Converted to a single canonical UTC timestamp so month/day/hour bucketing is comparable "
       "across records; local timestamp retained for calling-time-of-day analysis.")
calls.to_csv(f"{OUT}/golden_calls.csv", index=False)

# ---------------------------------------------------------------
# 5. CALL_ATTEMPTS
# ---------------------------------------------------------------
ca = pd.read_csv(f"{RAW}/call_attempts.csv")
raw_n = len(ca)
ca = ca.drop_duplicates()
after_exact = len(ca)
ca = ca.drop_duplicates(subset=["attempt_id"], keep="first")
record("call_attempts", "drop_exact_duplicate_rows", raw_n, after_exact, "Full-row duplicates removed.")
record("call_attempts", "dedupe_by_attempt_id", after_exact, len(ca), "attempt_id collisions kept as first-seen.")
ca.to_csv(f"{OUT}/golden_call_attempts.csv", index=False)

# ---------------------------------------------------------------
# 6. CALL_DISPOSITIONS (dedupe + canonicalize PTP/PROMISE_TO_PAY synonym)
# ---------------------------------------------------------------
cd = pd.read_csv(f"{RAW}/call_dispositions.csv")
raw_n = len(cd)
cd = cd.drop_duplicates()
after_exact = len(cd)
cd = cd.drop_duplicates(subset=["disposition_id"], keep="first")
after_id = len(cd)
n_ptp_variant = (cd["disposition_code"] == "PROMISE_TO_PAY").sum()
cd["disposition_code_raw"] = cd["disposition_code"]
cd["disposition_code"] = cd["disposition_code"].replace({"PROMISE_TO_PAY": "PTP"})
record("call_dispositions", "drop_exact_duplicate_rows", raw_n, after_exact, "Full-row duplicates removed.")
record("call_dispositions", "dedupe_by_disposition_id", after_exact, after_id, "disposition_id collisions kept as first-seen.")
record("call_dispositions", "canonicalize_ptp_code_synonym", after_id, after_id,
       f"'PROMISE_TO_PAY' and 'PTP' are the same disposition recorded under two different code "
       f"strings across all disposition_version values ({n_ptp_variant:,} rows relabeled to 'PTP'). "
       f"Uncorrected, this splits one true outcome into two and understates PTP-related rates.")
cd.to_csv(f"{OUT}/golden_call_dispositions.csv", index=False)

# ---------------------------------------------------------------
# 7. WHATSAPP / SMS / FIELD_VISITS / PTP / COMPLAINTS / ACCOUNT_STATUS_HISTORY
#    (exact-dup + natural-key dedupe only; no other known issues)
# ---------------------------------------------------------------
simple_tables = {
    "whatsapp_events": "whatsapp_event_id",
    "sms_events": "sms_event_id",
    "field_visits": "visit_id",
    "promises_to_pay": "ptp_id",
    "complaints": "complaint_id",
    "account_status_history": "history_id",
}
for tname, key in simple_tables.items():
    df = pd.read_csv(f"{RAW}/{tname}.csv")
    raw_n = len(df)
    df = df.drop_duplicates()
    after_exact = len(df)
    df = df.drop_duplicates(subset=[key], keep="first")
    record(tname, "drop_exact_duplicate_rows", raw_n, after_exact, "Full-row duplicates removed.")
    record(tname, f"dedupe_by_{key}", after_exact, len(df), f"{key} collisions kept as first-seen.")
    df.to_csv(f"{OUT}/golden_{tname}.csv", index=False)

# ---------------------------------------------------------------
# 8. PAYMENTS  (exact dup + duplicate payment_id; near-duplicate flagged, not auto-removed)
# ---------------------------------------------------------------
pay = pd.read_csv(f"{RAW}/payments.csv")
raw_n = len(pay)
pay = pay.drop_duplicates()
after_exact = len(pay)
pay = pay.drop_duplicates(subset=["payment_id"], keep="first")
after_id = len(pay)
record("payments", "drop_exact_duplicate_rows", raw_n, after_exact,
       f"{raw_n - after_exact} full-row duplicate payment events removed "
       f"(retry/ingestion duplicates inflating recovered amount).")
record("payments", "dedupe_by_payment_id", after_exact, after_id, "payment_id collisions kept as first-seen.")

pay["event_at"] = pd.to_datetime(pay["event_at"])
pay_sorted = pay.sort_values(["account_id", "amount", "event_at"])
pay_sorted["prev_time"] = pay_sorted.groupby(["account_id", "amount"])["event_at"].shift(1)
gap = (pay_sorted["event_at"] - pay_sorted["prev_time"]).dt.total_seconds()
pay_sorted["suspected_duplicate_retry"] = gap.notna() & (gap < 3600)
n_suspect = pay_sorted["suspected_duplicate_retry"].sum()
record("payments", "flag_suspected_retry_duplicates_not_removed", after_id, after_id,
       f"{n_suspect} payments share account+amount within 60 minutes of another payment "
       f"(classic double-submit/retry signature) but carry distinct payment_id/reference. "
       f"Flagged as suspected_duplicate_retry=True for downstream sensitivity analysis rather than "
       f"deleted outright, since a same-amount repeat within an hour could legitimately be two "
       f"different EMI/part-payments; removing them requires business confirmation.")
pay_sorted = pay_sorted.drop(columns=["prev_time"])
pay_sorted.to_csv(f"{OUT}/golden_payments.csv", index=False)

# ---------------------------------------------------------------
# 9. CAMPAIGNS / DAILY_TARGETING / VENDOR_TELEPHONY  (small clean tables)
# ---------------------------------------------------------------
for tname, key in [("campaigns", "campaign_id"), ("daily_targeting", "target_id"), ("vendor_telephony", "vendor_id")]:
    df = pd.read_csv(f"{RAW}/{tname}.csv")
    raw_n = len(df)
    df = df.drop_duplicates(subset=[key], keep="last")
    record(tname, f"dedupe_by_{key}", raw_n, len(df), "Kept last record per key (latest wins for reference/dimension tables).")
    df.to_csv(f"{OUT}/golden_{tname}.csv", index=False)

# ---------------------------------------------------------------
# WRITE DQ LOG
# ---------------------------------------------------------------
log_df = pd.DataFrame(log)
log_df.to_csv(f"{OUT}/_data_quality_log.csv", index=False)
with open(f"{OUT}/_data_quality_log.json", "w") as f:
    json.dump(log, f, indent=2, default=str)

print("Golden dataset build complete.")
print(log_df.to_string(index=False))
