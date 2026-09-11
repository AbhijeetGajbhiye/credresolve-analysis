"""
Reproduces the full SQL layer from scratch:
raw/*.csv -> credresolve.db -> staging views -> golden tables -> metric/driver views
-> re-exports golden_dataset/*.csv

Run from the repo root: python3 pipeline/run_sql_pipeline.py
"""
import sqlite3
import pandas as pd
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "raw")
SQL = os.path.join(ROOT, "sql")
GOLD = os.path.join(ROOT, "golden_dataset")
DB = os.path.join(ROOT, "credresolve.db")

FILES = ['borrowers','accounts','agents','agent_sessions','campaigns','daily_targeting',
    'calls','call_attempts','call_dispositions','whatsapp_events','sms_events',
    'field_visits','promises_to_pay','payments','vendor_telephony','complaints',
    'account_status_history']

def main():
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)

    print("Loading raw CSVs into SQLite...")
    for f in FILES:
        df = pd.read_csv(os.path.join(RAW, f"{f}.csv"))
        df.to_sql(f"raw_{f}", conn, if_exists="replace", index=False)
        print(f"  raw_{f:24s} {len(df):>8,} rows")

    for script in ["01_staging.sql", "02_golden_dataset.sql", "03_metrics.sql", "05_driver_analysis.sql"]:
        print(f"Executing {script} ...")
        conn.executescript(open(os.path.join(SQL, script)).read())
        conn.commit()
    print("(04_forensics.sql runs standalone diagnostic queries -- see the notebook for their output)")

    os.makedirs(GOLD, exist_ok=True)
    exports = {
        "golden_monthly_metrics": "select * from metric_monthly_panel",
        "golden_naive_vs_normalized_comparison": "select * from metric_naive_vs_normalized",
        "golden_channel_conversion_lasttouch": "select * from metric_channel_conversion",
        "golden_driver_risk_segment": "select * from driver_risk_segment",
        "golden_driver_dpd_bucket": "select * from driver_dpd_bucket",
        "golden_driver_loan_type": "select * from driver_loan_type",
        "golden_driver_geography": "select * from driver_geography",
        "golden_driver_channel": "select * from driver_channel",
        "golden_driver_vendor": "select * from driver_vendor",
        "golden_driver_calling_hour": "select * from driver_calling_hour",
        "golden_driver_attempt_frequency": "select * from driver_attempt_frequency",
        "golden_driver_agent_tenure": "select * from driver_agent_tenure",
    }
    for name, q in exports.items():
        pd.read_sql(q, conn).to_csv(os.path.join(GOLD, f"{name}.csv"), index=False)
    for t in ["golden_borrowers","golden_agents","golden_accounts","golden_calls",
              "golden_call_attempts","golden_call_dispositions","golden_whatsapp_events",
              "golden_sms_events","golden_field_visits","golden_promises_to_pay",
              "golden_complaints","golden_account_status_history","golden_payments",
              "golden_campaigns","golden_daily_targeting","golden_vendor_telephony",
              "golden_agent_sessions"]:
        pd.read_sql(f"select * from {t}", conn).to_csv(os.path.join(GOLD, f"{t}.csv"), index=False)

    print("\nDone. credresolve.db and golden_dataset/*.csv are up to date.")
    conn.close()

if __name__ == "__main__":
    main()
